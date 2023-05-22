abstract type NodeInfo end

"""
    AuxiliaryNodeInfo

Indicate the node is created by the compiler and not in the original BUGS model. These nodes
are only used to determine dependencies.
"""
struct AuxiliaryNodeInfo <: NodeInfo end

"""
    ConcreteNodeInfo

Define the information stored in each node of the BUGS graph.
"""
struct ConcreteNodeInfo <: NodeInfo
    node_type::VariableTypes
    link_function::Function
    node_function::Function
    node_args::Vector{VarName}
end

struct ConcreteNodeInfoConstruct
    vars
    link_functions
    node_functions
    node_args
end

function (constructor::ConcreteNodeInfoConstruct)(var::Var)
    if var in keys(constructor.vars)
        return ConcreteNodeInfo(
            constructor.vars[var],
            eval(constructor.link_functions[var]),
            eval(constructor.node_functions[var]),
            map(
                v -> AbstractPPL.VarName{v.name}(AbstractPPL.IdentityLens()),
                constructor.node_args[var],
            ),
        )
    else
        return AuxiliaryNodeInfo()
    end
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

function check_and_add_vertex!(g::BUGSGraph, v::VarName, data::NodeInfo)
    if haskey(g, v)
        if g[v] isa AuxiliaryNodeInfo && data isa ConcreteNodeInfo
            set_data!(g, v, data)
            # else # TODO: unstable test, link_function and node_function are anonymous functions
            #     @assert g[v].node_type == data.node_type && g[v].node_args == data.node_args
        end
    else
        add_vertex!(g, v, data)
    end
end

function scalarize_then_add_edge!(g::BUGSGraph, v::Var; lhs_or_rhs=:lhs)
    scalarized_v = vcat(scalarize(v)...)
    length(scalarized_v) == 1 && return nothing
    v = to_varname(v)
    for v_elem in map(to_varname, scalarized_v)
        add_vertex!(g, v_elem, AuxiliaryNodeInfo()) # may fail, but it's ok
        if lhs_or_rhs == :lhs
            add_edge!(g, v, v_elem)
        elseif lhs_or_rhs == :rhs
            add_edge!(g, v_elem, v)
        else
            error("Unknown argument $lhs_or_rhs")
        end
    end
end

function create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    g = MetaGraph(
        SimpleDiGraph{Int64}();
        weight_function=nothing,
        label_type=VarName,
        vertex_data_type=NodeInfo,
    )
    construct = ConcreteNodeInfoConstruct(vars, link_functions, node_functions, node_args)
    for l in keys(vars) # l for LHS variable
        l_vn = to_varname(l)
        check_and_add_vertex!(g, l_vn, construct(l))
        scalarize_then_add_edge!(g, l; lhs_or_rhs=:lhs)
        for r in dependencies[l]
            r_vn = to_varname(r)
            check_and_add_vertex!(g, r_vn, construct(r))
            add_edge!(g, r_vn, l_vn)
            scalarize_then_add_edge!(g, r; lhs_or_rhs=:rhs)
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
    try
        ret = get(env[sym], getlens(vn))
    catch _
    end
    return ismissing(ret) ? nothing : ret
end

function create_varinfo(g, sorted_nodes, vars, array_sizes, data, inits)
    vs = initialize_var_store(data, vars, array_sizes)
    vi = SimpleVarInfo(vs)
    return initialize_vi(g, sorted_nodes, vi, data, inits)
end

@inline function unpack(ni::NodeInfo)
    return ni.node_type, ni.link_function, ni.node_function, ni.node_args
end

function initialize_vi(g, sorted_nodes, vi, data, inits; transform_variables=true)
    vi = deepcopy(vi)
    parameters = VarName[]
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        ni isa ConcreteNodeInfo || continue
        node_type, link_function, node_function, args_vn = unpack(ni)
        args = [vi[x] for x in args_vn]
        if node_type == JuliaBUGS.Logical
            value = (node_function)(args...)
            @assert value isa Union{Number,Array{<:Number}}
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
                # println("initialization for $vn is not provided, sampling from prior");
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
    transform_type = if transform_variables
        DynamicPPL.DynamicTransformation
    else
        DynamicPPL.IdentityTransformation
    end
    return vi, VarInfoReconstruct{l,transform_type}(vi, parameters, g, sorted_nodes)
end

function _length(vn::VarName)
    getlens(vn) isa Setfield.IdentityLens && return 1
    return prod([length(index_range) for index_range in getlens(vn).indices])
end

struct VarInfoReconstruct{L,T<:DynamicPPL.AbstractTransformation}
    prototype::SimpleVarInfo
    parameters::Vector{VarName}
    g::BUGSGraph
    sorted_nodes::Vector{VarName}
end

function (re::VarInfoReconstruct{L,DynamicPPL.DynamicTransformation})(
    flattened_values::AbstractVector
) where {L}
    @assert length(flattened_values) == L
    vi, parameters, g, sorted_nodes = deepcopy(re.prototype),
    re.parameters, re.g,
    re.sorted_nodes
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
                value = if l == 1
                    flattened_values[current_idx]
                else
                    flattened_values[current_idx:(current_idx + l - 1)]
                end
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
function (re::VarInfoReconstruct{L,DynamicPPL.DynamicTransformation})() where {L}
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
