"""
    NodeInfo

Define the information stored in each node of the BUGS graph.
"""
struct NodeInfo
    node_type::VariableTypes
    link_function::Function
    node_function::Function
    node_args::Vector{VarName}
end

"""
    BUGSGraph

The graph object for a BUGS model. Just an alias of `MetaGraph` with specified types.
"""
const BUGSGraph = MetaGraph{
    Int64,SimpleDiGraph{Int64},VarName,NodeInfo,Nothing,Nothing,Nothing,Float64
}

function to_varname(v::Scalar)
    lens = AbstractPPL.IdentityLens()
    return AbstractPPL.VarName{v.name}(lens)
end
function to_varname(v::Var)
    lens = AbstractPPL.IndexLens(v.indices)
    return AbstractPPL.VarName{v.name}(lens)
end

function create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    g = MetaGraph(
        SimpleDiGraph{Int64}();
        weight_function=nothing,
        label_type=VarName,
        vertex_data_type=NodeInfo,
    )
    variables = keys(vars);
    for var in variables
        vn = to_varname(var)
        to_varname_dropindex(v::Var) = AbstractPPL.VarName{v.name}(AbstractPPL.IdentityLens())
        vn_args = map(to_varname_dropindex, node_args[var]) # args are variables without indices
        node_data = NodeInfo(
            vars[var], eval(link_functions[var]), eval(node_functions[var]), vn_args
        )
        add_vertex!(g, vn, node_data)
    end
    for var in variables
        for dep in dependencies[var]
            dep_vn = to_varname(dep)
            vn = to_varname(var)
            add_edge!(g, dep_vn, vn)
        end
    end
    return g
end

function initialize_var_store(data, vars, array_sizes)
    var_store = Dict{VarName,Any}()
    array_vn(k::Symbol) = AbstractPPL.VarName{Symbol(k)}(AbstractPPL.IdentityLens())
    for (k, v) in data
        vn = array_vn(k)
        var_store[vn] = v
    end
    for (k, v) in array_sizes
        vn = array_vn(k)
        haskey(var_store, vn) || (var_store[vn] = zeros(v...))
    end
    for v in keys(vars)
        if v isa Scalar
            vn = to_varname(v)
            var_store[vn] = 0.0 # TODO: assume all scalars are floating point numbers now
        end
    end
    return var_store
end

_inv(::typeof(logit)) = probit
_inv(::typeof(cloglog)) = cloglog
_inv(::typeof(log)) = exp
function probit end
_inv(::typeof(probit)) = logit
_inv(identity) = identity

function evaluate(env::Dict, vn::VarName)
    sym = getsym(vn)
    ret = nothing
    try ret = get(env[sym], getlens(vn)) catch _ end
    return ret
end

function create_varinfo(g, sorted_nodes, vars, array_sizes, data, inits)
    vs = initialize_var_store(data, vars, array_sizes)
    vi = SimpleVarInfo(vs)
    return initialize_vi(g, sorted_nodes, vi, data, inits)
end

@inline unpack(ni::NodeInfo) = ni.node_type, ni.link_function, ni.node_function, ni.node_args

function initialize_vi(g, sorted_nodes, vi, data, inits; transform_variables=true)
    vi = deepcopy(vi)
    parameters = VarName[]
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        node_type, link_function, node_function, args_vn = unpack(ni)
        args = [vi[x] for x in args_vn]
        if node_type == JuliaBUGS.Logical
            value = (node_function)(args...)
            @assert value isa Union{Number, Array{<:Number}}
            vi = setindex!!(vi, value, vn)
        else
            dist = (node_function)(args...)
            value = evaluate(data, vn)
            isnothing(value) && push!(parameters, vn)
            isnothing(value) && (value = evaluate(inits, vn))
            if !isnothing(value)
                logp += logpdf(dist, (link_function)(value))
                vi = setindex!!(vi, value, vn)
            else
                println("initialization for $vn is not provided, sampling from prior");
                value = rand(dist)
                logp += logpdf(dist, value)
                value = _inv(link_function)(value)
                vi = setindex!!(vi, value, vn)
            end
        end
    end
    l = sum([_length(x) for x in parameters])
    vi = @set vi.logp = logp
    vi = DynamicPPL.settrans!!(vi, transform_variables)
    transform_type = transform_variables ? DynamicPPL.DynamicTransformation : DynamicPPL.IdentityTransformation
    return vi, VarInfoReconstruct{l, transform_type}(vi, parameters, g, sorted_nodes)
end

function _length(vn::VarName)
    getlens(vn) isa Setfield.IdentityLens && return 1
    return prod([length(index_range) for index_range in getlens(vn).indices])
end

struct VarInfoReconstruct{L, T<:DynamicPPL.AbstractTransformation}
    prototype::SimpleVarInfo
    parameters::Vector{VarName}
    g::BUGSGraph
    sorted_nodes::Vector{VarName}
end

function (re::VarInfoReconstruct{L, DynamicPPL.DynamicTransformation})(flattened_values::AbstractVector) where L
    @assert length(flattened_values) == L
    vi, parameters, g, sorted_nodes = deepcopy(re.prototype), re.parameters, re.g, re.sorted_nodes
    current_idx = 1
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        node_type, link_function, node_function, args_vn = unpack(ni)
        args = [vi[x] for x in args_vn]
        
        if node_type == JuliaBUGS.Logical
            value = node_function(args...)
            setindex!!(vi, value, vn)
        else
            dist = node_function(args...)
            if vn in parameters
                l = _length(vn)
                value = l == 1 ? flattened_values[current_idx] : flattened_values[current_idx:current_idx+l-1]
                value = invlink(dist, value)
                current_idx += l
                setindex!!(vi, value, vn)
                logp += logpdf(dist, (link_function)(value))
            else
                value = vi[vn]
                logp += logpdf(dist, (link_function)(value))
            end
        end
    end
    return @set vi.logp = logp
end

# `re` with no argument is ancestral sampling
function (re::VarInfoReconstruct{L, DynamicPPL.DynamicTransformation})() where L
    vi, g, sorted_nodes = deepcopy(re.prototype), re.parameters, re.g, re.sorted_nodes
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        node_type, link_function, node_function, args_vn = unpack(ni)
        args = [vi[x] for x in args_vn]
        if node_type == JuliaBUGS.Logical
            value = node_function(args...)
            setindex!!(vi, value, vn)
        else
            dist = node_function(args...)
            value = rand(dist)
            logp += logpdf(dist, value)
            setindex!!(vi, _inv(link_function)(value), vn)
        end
    end
    return @set vi.logp = logp
end