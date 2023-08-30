abstract type NodeInfo end

"""
    AuxiliaryNodeInfo

Indicate the node is created by the compiler and not in the original BUGS model. These nodes
are only used to determine dependencies.

E.g., x[1:2] ~ dmnorm(...); y = x[1] + 1
In this case, x[1] is a auxiliary node, because it doesn't appear on the LHS of any expression.
But we still need to introduce it to determine the dependency between `y` and `x[1:2]`.

In the current implementation, `AuxiliaryNodeInfo` is only used when constructing the graph,
and will all be removed right before returning the graph. 
"""
struct AuxiliaryNodeInfo <: NodeInfo end

"""
    ConcreteNodeInfo

Defines the information stored in each node of the BUGS graph, encapsulating the essential characteristics 
and functions associated with a node within the BUGS model's dependency graph.

# Fields

- `node_type::VariableTypes`: Specifies whether the node is a stochastic or logical variable.
- `link_function_expr::Union{Expr,Symbol}`: The link function expression.
- `node_function_expr::Expr`: The node function expression.
- `node_args::Vector{VarName}`: A vector containing the names of the variables that are 
    arguments to the node function.

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

The `BUGSGraph` object represents the graph structure for a BUGS model. It is a type alias for
[`MetaGraphsNext.MetaGraph`](https://juliagraphs.org/MetaGraphsNext.jl/dev/api/#MetaGraphsNext.MetaGraph)
with node type specified to [`ConcreteNodeInfo`](@ref).
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
        # The use of AuxiliaryNodeInfo is also to save computation, becasue otherwise, 
        # every time we introduce a new node, we need to check `subsumes` or by all the existing nodes.
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
    check_undeclared_variables(g, vars)
    remove_auxiliary_nodes!(g)
    return g
end

"""
    check_undeclared_variables

Check for undeclared variables within the model definition
"""
function check_undeclared_variables(g::BUGSGraph, vars)
    undeclared_vars = VarName[]
    for v in labels(g)
        if g[v] isa AuxiliaryNodeInfo
            children = outneighbor_labels(g, v)
            parents = inneighbor_labels(g, v)
            if isempty(parents) || isempty(children)
                if !any(
                    AbstractPPL.subsumes(u, v) || AbstractPPL.subsumes(v, u) for # corner case x[1:1] and x[1], e.g. Leuk
                    u in to_varname.(keys(vars))
                )
                    push!(undeclared_vars, v)
                end
            end
        end
    end
    if !isempty(undeclared_vars)
        error("Undeclared variables: $(string.(Symbol.(undeclared_vars)))")
    end
end

function remove_auxiliary_nodes!(g::BUGSGraph)
    for v in collect(labels(g))
        if g[v] isa AuxiliaryNodeInfo
            # fix dependencies
            children = outneighbor_labels(g, v)
            parents = inneighbor_labels(g, v)
            for c in children
                for p in parents
                    @assert !any(x -> x isa AuxiliaryNodeInfo, (g[c], g[p])) "Auxiliary nodes should not have neighbors that are also auxiliary nodes, but at least one of $(g[c]) and $(g[p]) are."
                    add_edge!(g, p, c)
                end
            end
            delete!(g, v)
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
        if lhs_or_rhs == :lhs # if an edge exist between v and scalaized elements, don't add again
            !Graphs.has_edge(g, code_for(g, v_elem), code_for(g, v)) &&
                add_edge!(g, v, v_elem)
        elseif lhs_or_rhs == :rhs
            !Graphs.has_edge(g, code_for(g, v), code_for(g, v_elem)) &&
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
    find_generated_vars(g::BUGSGraph)

Return all the logical variables without stochastic descendants. The values of these variables 
do not affect sampling process. These variables are called "generated quantities" traditionally.
"""
function find_generated_vars(g)
    graph_roots = VarName[] # root nodes of the graph
    for n in labels(g)
        if isempty(outneighbor_labels(g, n))
            push!(graph_roots, n)
        end
    end

    generated_vars = VarName[]
    for n in graph_roots
        if g[n].node_type == Logical
            push!(generated_vars, n) # graph roots that are Logical nodes are generated variables
            find_generated_vars_recursive_helper(g, n, generated_vars)
        end
    end
    return generated_vars
end

function find_generated_vars_recursive_helper(g, n, generated_vars)
    if n in generated_vars # already visited
        return nothing
    end
    for p in inneighbor_labels(g, n) # parents
        if p in generated_vars # already visited
            continue
        end
        if g[p].node_type == Stochastic
            continue
        end # p is a Logical Node
        if !any(x -> g[x].node_type == Stochastic, outneighbor_labels(g, p)) # if the node has stochastic children, it is not a root
            push!(generated_vars, p)
        end
        find_generated_vars_recursive_helper(g, p, generated_vars)
    end
end

# AbstractBUGSModel can't be a subtype of AbstractProbabilisticProgram (<: AbstractMCMC.AbstractModel)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

"""
    BUGSModel

The `BUGSModel` object is used for inference and represents the output of compilation. It fully implements the
[`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl) interface.

# Fields

- `param_length::Int`: The length of the parameters vector, defining the number of parameters in the model.
- `varinfo::SimpleVarInfo`: An instance of 
    [`DynamicPPL.SimpleVarInfo`](https://turinglang.org/DynamicPPL.jl/dev/api/#DynamicPPL.SimpleVarInfo), 
    specifically a dictionary that maps both data and value of variables in the model to the corresponding values.
- `parameters::Vector{VarName}`: A vector containing the names of the parameters in the model. These parameters are defined to be 
    stochastic variables that are not observed.
- `g::BUGSGraph`: An instance of [`BUGSGraph`](@ref), representing the dependency graph of the model.
- `sorted_nodes::Vector{VarName}`: A vector containing the names of all the variables in the model, sorted in topological order.

"""
struct BUGSModel <: AbstractBUGSModel
    param_length::Int
    varinfo::SimpleVarInfo
    parameters::Vector{VarName}
    g::BUGSGraph
    sorted_nodes::Vector{VarName}
end

# Resolves: setindex!!([1 2; 3 4], [2 3; 4 5], 1:2, 1:2) # returns 2×2 Matrix{Any}
# Alternatively, can overload BangBang.possible(
#     ::typeof(BangBang._setindex!), ::C, ::T, ::Vararg
# )
# to allow mutation, but the current solution seems create less possible problems, albeit less efficient.
function BangBang.NoBang._setindex(xs::AbstractArray, v::AbstractArray, I...)
    T = promote_type(eltype(xs), eltype(v))
    ys = similar(xs, T)
    if eltype(xs) !== Union{}
        copy!(ys, xs)
    end
    ys[I...] = v
    return ys
end

"""
    param_names(m::BUGSModel)

Return the names of the parameters in the model.
"""
param_names(m::BUGSModel) = m.parameters

"""
    all_variables(m::BUGSModel)

Return the names of all the variables in the model.
"""
all_variables(m::BUGSModel) = labels(m.g)

"""
    generated_variables(m::BUGSModel)

Return the names of the generated variables in the model.
"""
generated_variables(m::BUGSModel) = find_generated_vars(m.g)

struct UninitializedVariableError <: Exception
    msg::String
end

function BUGSModel(g, sorted_nodes, vars, array_sizes, data, inits)
    vs = initialize_var_store(data, vars, array_sizes)
    vi = SimpleVarInfo(vs)
    parameters = VarName[]
    for vn in sorted_nodes
        @assert !(g[vn] isa AuxiliaryNodeInfo) "Auxiliary nodes should not be in the graph, but $(g[vn]) is."

        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = try
                _eval(expr, args)
            catch _
                rethrow(
                    UninitializedVariableError(
                        "Encounter error when evaluating the RHS of $vn. Try to initialize variables $(join(collect(keys(args)), ", ")) directly first if not yet.",
                    ),
                )
            end
            @assert value isa Union{Real,Array{<:Real}} "$value is not a number or array"
            vi = setindex!!(vi, value, vn)
        else
            dist = try
                _eval(expr, args)
            catch _
                rethrow(
                    UninitializedVariableError(
                        "Encounter support error when evaluating the distribution of $vn. Try to initialize variables $(join(collect(keys(args)), ", ")) first if not yet.",
                    ),
                )
            end
            value = evaluate(vn, data)
            isnothing(value) && push!(parameters, vn)
            isnothing(value) && (value = evaluate(vn, inits))
            if !isnothing(value)
                vi = setindex!!(vi, value, vn)
            else
                vi = setindex!!(vi, rand(dist), vn)
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
        if !haskey(var_store, vn)
            # var_store[vn] = zeros(v...)
            var_store[vn] = Array{Float64}(undef, v...)
        end
    end
    for v in keys(vars)
        if v isa Scalar
            vn = to_varname(v)
            var_store[vn] = 0.0
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

! Should not be used outside of the usage demonstrated in this file.

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

    function MarkovBlanketCoveredBUGSModel(m::BUGSModel, var_group::Union{VarName, Vector{VarName}})
        var_group = var_group isa VarName ? [var_group] : var_group
        non_vars = VarName[]
        logical_vars = VarName[]
        for var in var_group
            if var ∉ labels(m.g)
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
        new(param_length, blanket_with_vars, m)
    end
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
SamplingContext() = SamplingContext(Random.default_rng())

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
        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
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
        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
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

        ni = g[vn]
        @unpack node_type, link_function_expr, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
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
