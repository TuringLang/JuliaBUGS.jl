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
    link_function_expr::Union{Expr,Symbol}
    node_function_expr::Expr
    node_args::Vector{VarName}
end

function ConcreteNodeInfo(var::Var, vars, link_functions, node_functions, node_args)
    return ConcreteNodeInfo(
        vars[var],
        link_functions[var],
        node_functions[var],
        map(v -> AbstractPPL.VarName{v.name}(AbstractPPL.IdentityLens()), node_args[var]),
    )
end

function NodeInfo(var::Var, vars, link_functions, node_functions, node_args)
    if var in keys(vars)
        return ConcreteNodeInfo(var, vars, link_functions, node_functions, node_args)
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

function BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    g = MetaGraph(
        SimpleDiGraph{Int64}();
        weight_function=nothing,
        label_type=VarName,
        vertex_data_type=NodeInfo,
    )
    for l in keys(vars) # l for LHS variable
        l_vn = to_varname(l)
        check_and_add_vertex!(
            g, l_vn, NodeInfo(l, vars, link_functions, node_functions, node_args)
        )
        scalarize_then_add_edge!(g, l; lhs_or_rhs=:lhs)
        for r in dependencies[l]
            r_vn = to_varname(r)
            check_and_add_vertex!(
                g, r_vn, NodeInfo(r, vars, link_functions, node_functions, node_args)
            )
            add_edge!(g, r_vn, l_vn)
            scalarize_then_add_edge!(g, r; lhs_or_rhs=:rhs)
        end
    end
    # remove_auxiliary_nodes!(g)
    return g
end

function remove_auxiliary_nodes!(g::BUGSGraph)
    for v in labels(g)
        if g[v] isa AuxiliaryNodeInfo
            # fix dependencies
            children = outneighbor_labels(g, v)
            parents = inneighbor_labels(g, v)
            for c in children
                for p in parents
                    add_edge!(g, p, c)
                end
            end
            remove_vertex!(g, v)
        end
    end
end

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
        data isa AuxiliaryNodeInfo && return nothing
        if g[v] isa AuxiliaryNodeInfo
            set_data!(g, v, data)
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
        add_vertex!(g, v_elem, AuxiliaryNodeInfo()) # may fail, in that case, the existing node may be concrete, so we don't need to add it
        if lhs_or_rhs == :lhs
            add_edge!(g, v, v_elem)
        elseif lhs_or_rhs == :rhs
            add_edge!(g, v_elem, v)
        else
            error("Unknown argument $lhs_or_rhs")
        end
    end
end

"""
    _eval(expr, env)

`_eval` mimics `Base.eval`, but uses precompiled functions. This is possible because the expressions we want to 
evaluate only have two kinds of expressions: function calls and indexing.
`env` is a data structure mapping symbols in `expr` to values, values can be arrays or scalars.
"""
function _eval(expr::Number, env)
    return expr
end
function _eval(expr::Symbol, env)
    if expr == :nothing
        return nothing
    elseif expr == :(:)
        return Colon()
    else # intentional strict, all corner cases should be handled above
        return env[expr]
    end
end
function _eval(expr::Expr, env)
    if Meta.isexpr(expr, :call)
        f = expr.args[1]
        args = [_eval(arg, env) for arg in expr.args[2:end]]
        if f isa Expr # `JuliaBUGS.some_function` like
            f = f.args[2].value
        end
        return getfield(JuliaBUGS, f)(args...) # assume all functions used are available under `JuliaBUGS`
    elseif Meta.isexpr(expr, :ref)
        array = _eval(expr.args[1], env)
        indices = [_eval(arg, env) for arg in expr.args[2:end]]
        return array[indices...]
    elseif Meta.isexpr(expr, :block)
        return _eval(expr.args[end], env)
    else
        error("Unknown expression type: $expr")
    end
end
function _eval(expr, env)
    return error("Unknown expression type: $expr of type $(typeof(expr))")
end

"""
    find_logical_roots(g::BUGSGraph)

Return all the logical variables without stochastic descendants. The values of these variables 
do not affect sampling process. These variables are "generated quantities" traditionally.
"""
function find_logical_roots(g)
    graph_roots = VarName[] # root nodes of the graph
    for n in labels(g)
        if isempty(outneighbor_labels(g, n))
            push!(graph_roots, n)
        end
    end

    # what are these variables
    # variables's children are either roots or recursively defined
    logical_roots = VarName[]
    for n in graph_roots
        if g[n] isa AuxiliaryNodeInfo
            error(
                "AuxiliaryNodeInfo: $(g[n]) is a root of the graph, it shouldn't be an AuxiliaryNodeInfo",
            )
        end
        if g[n].node_type == Stochastic
            continue
        else
            recursive_helper(g, n, logical_roots)
        end
    end
    return logical_roots
end

function recursive_helper(g, n, logical_roots)
    if n in logical_roots
        return nothing
    end
    push!(logical_roots, n)
    parents = inneighbor_labels(g, n)
    for p in parents
        if p in logical_roots # already visited
            continue
        end
        if !(g[p] isa AuxiliaryNodeInfo) && g[p].node_type == Stochastic
            continue
        end
        # then `p` is either a logical node or an auxiliary node
        if any(x -> g[x].node_type == Stochastic, outneighbor_labels(g, p)) # if the node has stochastic children, it is not a root
            continue
        elseif !(g[p] isa AuxiliaryNodeInfo) # g[p].node_type == Logical
            push!(logical_roots, p)
        end
        recursive_helper(g, p, logical_roots)
    end
end

# TODO: observation stochastic variables form a barrier such that, assumed stochastic variable that are
# descendants of those variables do not affect the log joint density. This is not implemented yet.

abstract type AbstractBUGSModel <: AbstractPPL.AbstractProbabilisticProgram end

"""
    BUGSModel

The model object for a BUGS model.
"""
struct BUGSModel <: AbstractBUGSModel
    param_length::Int
    varinfo::SimpleVarInfo
    parameters::Vector{VarName}
    g::BUGSGraph
    sorted_nodes::Vector{VarName}
end

function BUGSModel(g, sorted_nodes, vars, array_sizes, data, inits)
    vs = initialize_var_store(data, vars, array_sizes)
    vi = SimpleVarInfo(vs)
    parameters = VarName[]
    for vn in sorted_nodes
        g[vn] isa AuxiliaryNodeInfo && continue

        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            @assert value isa Union{Number,Array{<:Number}} "$value is not a number or array"
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            value = evaluate(vn, data)
            isnothing(value) && push!(parameters, vn)
            isnothing(value) && (value = evaluate(vn, inits))
            if !isnothing(value)
                vi = setindex!!(vi, value, vn)
            else
                # if not initialized, just set to zeros
                vi = setindex!!(vi, length(dist) == 1 ? 0.0 : zeros(length(dist)), vn)
            end
        end
    end
    l = isempty(parameters) ? 0 : sum(_length(x) for x in parameters)
    return BUGSModel(l, vi, parameters, g, sorted_nodes)
end

function initialize_var_store(data, vars, array_sizes)
    var_store = Dict{VarName,Any}()
    array_vn(k::Symbol) = AbstractPPL.VarName{Symbol(k)}(AbstractPPL.IdentityLens())
    for k in keys(data)
        v = data[k]
        vn = array_vn(k)
        var_store[vn] = v
    end
    for k in keys(array_sizes)
        v = array_sizes[k]
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

function DynamicPPL.settrans!!(m::BUGSModel, if_trans::Bool)
    return @set m.varinfo = DynamicPPL.settrans!!(m.varinfo, if_trans)
end

function evaluate(vn::VarName, env)
    sym = getsym(vn)
    ret = nothing
    try
        ret = get(env[sym], getlens(vn))
    catch _
    end
    return ismissing(ret) ? nothing : ret
end

"""
    _length(vn::VarName)

Return the length of a possible variable identified by `vn`.
Only valid if `vn` is:
    - a scalar
    - an array indexing whose indices are concrete(no `start`, `end`, `:`)

! Should not be used outside of the usage demonstrate in this file.

"""
function _length(vn::VarName)
    getlens(vn) isa Setfield.IdentityLens && return 1
    return prod([length(index_range) for index_range in getlens(vn).indices])
end

function get_params_varinfo(m::BUGSModel)
    return get_params_varinfo(m, m.varinfo)
end
function get_params_varinfo(m::BUGSModel, vi::SimpleVarInfo)
    d = Dict{VarName,Any}()
    for param in m.parameters
        d[param] = vi[param]
    end
    return SimpleVarInfo(d, vi.logp, vi.transformation)
end

"""
    MarkovBlanketCoveredBUGSModel

The model object for a BUGS model with Markov blanket covered.
The `blanket` field is a vector of `VarName` that contains the Markov blanket of the variables and 
the variables themselves.
"""
struct MarkovBlanketCoveredBUGSModel <: AbstractBUGSModel
    param_length::Int
    blanket::Vector{VarName}
    model::BUGSModel
end

"""
    MarkovBlanketCoveredBUGSModel(m::BUGSModel, var_group)

`var_group` can be a single `VarName` or a vector of `VarName`. The variable in `var_group` 
must be a variable in the model; logical variables in `var_group` will not error, but will be ignored.
"""
function MarkovBlanketCoveredBUGSModel(m::BUGSModel, var_group::VarName)
    return MarkovBlanketCoveredBUGSModel(m, VarName[var_group])
end
function MarkovBlanketCoveredBUGSModel(m::BUGSModel, var_group::Vector{VarName})
    non_vars = VarName[]
    logical_vars = VarName[]
    for var in var_group
        if var ∉ labels(m.g) || m.g[var] isa AuxiliaryNodeInfo
            push!(non_vars, var)
        elseif m.g[var].node_type == Logical
            push!(logical_vars, var)
        end
    end
    isempty(non_vars) || error("Variables $(non_vars) are not in the model")
    isempty(logical_vars) ||
        warn("Variables $(logical_vars) are not stochastic variables, they will be ignored")
    blanket = markov_blanket(m.g, var_group)
    blanket_with_vars = union(blanket, var_group)
    params = [vn for vn in blanket_with_vars if vn in m.parameters]
    param_length = isempty(params) ? 0 : sum(_length(vn) for vn in params)
    return MarkovBlanketCoveredBUGSModel(param_length, blanket_with_vars, m)
end

"""
    markov_blanket(g::BUGSModel, v)

Find the Markov blanket of `v` in `g`. `v` can be a single `VarName` or a vector of `VarName`.
The Markov Blanket of a variable is the set of variables that shield the variable from the rest of the
network. Effectively, the Markov blanket of a variable is the set of its parents, its children, and
its children's other parents (reference: https://en.wikipedia.org/wiki/Markov_blanket).

In the case of vector, the Markov Blanket is the union of the Markov Blankets of each variable 
minus the variables themselves (reference: Liu, X.-Q., & Liu, X.-S. (2018). Markov Blanket and Markov 
Boundary of Multiple Variables. Journal of Machine Learning Research, 19(43), 1–50.)
"""
function markov_blanket(g, v::VarName)
    parents = stochastic_inneighbors(g, v)
    children = stochastic_outneighbors(g, v)
    co_parents = VarName[]
    for p in children
        co_parents = vcat(co_parents, stochastic_inneighbors(g, p))
    end
    blanket = unique(vcat(parents, children, co_parents...))
    return [x for x in blanket if x != v]
end

function markov_blanket(g, v)
    blanket = VarName[]
    for vn in v
        blanket = vcat(blanket, markov_blanket(g, vn))
    end
    return [x for x in unique(blanket) if x ∉ v]
end

"""
    stochastic_neighbors(g::BUGSModel, c::VarName, f)
   
Internal function to find all the stochastic neighbors (parents or children), returns a vector of
`VarName` containing the stochastic neighbors and the logical variables along the paths.
"""
function stochastic_neighbors(
    g::BUGSGraph,
    v::VarName,
    f::Union{
        typeof(MetaGraphsNext.inneighbor_labels),typeof(MetaGraphsNext.outneighbor_labels)
    },
)
    stochastic_neighbors_vec = VarName[]
    logical_en_route = VarName[] # logical variables
    for u in f(g, v)
        if g[u] isa ConcreteNodeInfo
            if g[u].node_type == Stochastic
                push!(stochastic_neighbors_vec, u)
            else
                push!(logical_en_route, u)
                ns = stochastic_neighbors(g, u, f)
                for n in ns
                    push!(stochastic_neighbors_vec, n)
                end
            end
        else
            # auxiliary nodes are not counted as logical nodes
            ns = stochastic_neighbors(g, u, f)
            for n in ns
                push!(stochastic_neighbors_vec, n)
            end
        end
    end
    return [stochastic_neighbors_vec..., logical_en_route...]
end

"""
    stochastic_inneighbors(g::BUGSModel, v::VarName)

Find all the stochastic inneighbors (parents) of `v`.
"""
function stochastic_inneighbors(g, v)
    return stochastic_neighbors(g, v, MetaGraphsNext.inneighbor_labels)
end

"""
    stochastic_outneighbors(g::BUGSModel, v::VarName)

Find all the stochastic outneighbors (children) of `v`.
"""
function stochastic_outneighbors(g, v)
    return stochastic_neighbors(g, v, MetaGraphsNext.outneighbor_labels)
end

"""
    DefaultContext

Use values in varinfo to compute the log joint density.
"""
struct DefaultContext <: AbstractPPL.AbstractContext end

"""
    SamplingContext

Do an ancestral sampling of the model parameters. Also accumulate log joint density.
"""
struct SamplingContext <: AbstractPPL.AbstractContext
    rng::Random.AbstractRNG
end

"""
    LogDensityContext

Use the given values to compute the log joint density.
"""
struct LogDensityContext <: AbstractPPL.AbstractContext end

function AbstractPPL.evaluate!!(model::BUGSModel, rng::Random.AbstractRNG)
    return evaluate!!(model, SamplingContext(rng))
end
function AbstractPPL.evaluate!!(model::BUGSModel, ctx::SamplingContext)
    @unpack param_length, varinfo, parameters, g, sorted_nodes = model
    vi = deepcopy(varinfo)
    logp = 0.0
    for vn in sorted_nodes
        g[vn] isa AuxiliaryNodeInfo && continue

        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            if link_function_expr != :identity
                dist = transformed(dist, bijector_of_link_function(link_function_expr))
            end
            value = rand(ctx.rng, dist)
            if DynamicPPL.transformation(vi) == DynamicPPL.DynamicTransformation()
                value_transformed, logabsdetjac = with_logabsdet_jacobian(
                    DynamicPPL.inverse(bijector(dist)), val
                )
                logp += logpdf(dist, value_transformed) + logabsdetjac
            else
                logp += logpdf(dist, value)
            end
            vi = setindex!!(vi, value, vn)
        end
    end
    return @set vi.logp = logp
end

AbstractPPL.evaluate!!(model::BUGSModel) = AbstractPPL.evaluate!!(model, DefaultContext())
function AbstractPPL.evaluate!!(model::BUGSModel, ::DefaultContext)
    @unpack param_length, varinfo, parameters, g, sorted_nodes = model
    vi = deepcopy(varinfo)
    logp = 0.0
    for vn in sorted_nodes
        g[vn] isa AuxiliaryNodeInfo && continue

        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        node_type == JuliaBUGS.Logical && continue
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        dist = _eval(expr, args)
        if link_function_expr != :identity
            dist = transformed(dist, bijector_of_link_function(link_function_expr))
        end
        value = vi[vn]
        if DynamicPPL.transformation(vi) isa DynamicPPL.DynamicTransformation
            value_transformed, logabsdetjac = with_logabsdet_jacobian(
                Bijectors.inverse(bijector(dist)), value
            )
            logp += logpdf(dist, value_transformed) + logabsdetjac
        else
            logp += logpdf(dist, value)
        end
    end
    return @set vi.logp = logp
end

function AbstractPPL.evaluate!!(
    model::BUGSModel, ::LogDensityContext, flattened_values::AbstractVector
)
    @assert length(flattened_values) == model.param_length
    @unpack param_length, varinfo, parameters, g, sorted_nodes = model
    vi = deepcopy(varinfo)
    current_idx = 1
    logp = 0.0
    for vn in sorted_nodes
        g[vn] isa AuxiliaryNodeInfo && continue

        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            if link_function_expr != :identity
                dist = transformed(dist, bijector_of_link_function(link_function_expr))
            end
            if vn in parameters # the value of parameter variables are stored in flattened_values
                l = _length(vn)
                value_transformed = if l == 1
                    flattened_values[current_idx]
                else
                    flattened_values[current_idx:(current_idx + l - 1)]
                end
                current_idx += l

                value = invlink(dist, value_transformed)
                if DynamicPPL.transformation(vi) == DynamicPPL.DynamicTransformation()
                    value_transformed, logabsdetjac = with_logabsdet_jacobian(
                        Bijectors.inverse(bijector(dist)), value
                    )
                    logp += logpdf(dist, value_transformed) + logabsdetjac
                else
                    logp += logpdf(dist, value)
                end
                vi = setindex!!(vi, value, vn)
            else
                logp += logpdf(dist, vi[vn])
            end
        end
    end
    return @set vi.logp = logp
end

function AbstractPPL.evaluate!!(model::MarkovBlanketCoveredBUGSModel, ::DefaultContext)
    @unpack param_length, varinfo, parameters, g, sorted_nodes = model.model
    vi = deepcopy(varinfo)
    logp = 0.0
    for vn in sorted_nodes
        vn in model.blanket || continue
        g[vn] isa AuxiliaryNodeInfo && continue

        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        node_type == JuliaBUGS.Logical && continue
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        dist = _eval(expr, args)
        if link_function_expr != :identity
            dist = transformed(dist, bijector_of_link_function(link_function_expr))
        end
        value = vi[vn]
        if DynamicPPL.transformation(vi) isa DynamicPPL.DynamicTransformation
            value_transformed, logabsdetjac = with_logabsdet_jacobian(
                Bijectors.inverse(bijector(dist)), value
            )
            logp += logpdf(dist, value_transformed) + logabsdetjac
        else
            logp += logpdf(dist, value)
        end
    end
    return @set vi.logp = logp
end

function AbstractPPL.evaluate!!(
    model::MarkovBlanketCoveredBUGSModel,
    ::LogDensityContext,
    flattened_values::AbstractVector,
)
    @assert length(flattened_values) == model.param_length
    @unpack param_length, varinfo, parameters, g, sorted_nodes = model.model
    vi = deepcopy(varinfo)
    current_idx = 1
    logp = 0.0
    for vn in sorted_nodes
        vn in model.blanket || continue
        g[vn] isa AuxiliaryNodeInfo && continue

        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            if link_function_expr != :identity
                dist = transformed(dist, bijector_of_link_function(link_function_expr))
            end
            if vn in parameters # the value of parameter variables are stored in flattened_values
                l = _length(vn)
                value_transformed = if l == 1
                    flattened_values[current_idx]
                else
                    flattened_values[current_idx:(current_idx + l - 1)]
                end
                current_idx += l

                value = invlink(dist, value_transformed)
                if DynamicPPL.transformation(vi) == DynamicPPL.DynamicTransformation()
                    value_transformed, logabsdetjac = with_logabsdet_jacobian(
                        Bijectors.inverse(bijector(dist)), value
                    )
                    logp += logpdf(dist, value_transformed) + logabsdetjac
                else
                    logp += logpdf(dist, value)
                end
                vi = setindex!!(vi, value, vn)
            else
                logp += logpdf(dist, vi[vn])
            end
        end
    end
    return @set vi.logp = logp
end
