"""
    NodeInfo

Abstract type for storing node information in the BUGS model's dependency graph.
"""
abstract type NodeInfo end

"""
    is_logical

Determines if a node is logical. This is not model or context dependent.
"""
is_logical

"""
    eval(m::Module, ni::NodeInfo, env)

Evaluates a node. If the node is not logical, it returns a Distribution.
"""
function eval(m::Module, ni::NodeInfo, env) end

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

function is_logical(ni::ConcreteNodeInfo)
    return ni.node_type == Logical
end

"""
    eval([m::Module, ]ni::ConcreteNodeInfo, vi)

Evaluate a node under a specified module `m`. If no module is provided, the default module used is JuliaBUGS.
This function unpacks the node information from `ni` and evaluates the node function expression using the arguments
from the provided `vi` (variable information).
"""
function eval(ni::ConcreteNodeInfo, vi)
    return eval(JuliaBUGS, ni, vi)
end
function eval(m::Module, ni::ConcreteNodeInfo, vi)
    @unpack node_type, link_function_expr, node_function_expr, node_args = ni
    args = Dict(getsym(arg) => vi[arg] for arg in node_args)
    expr = node_function_expr.args[2]
    return _eval(m, expr, args)
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
            g, l_vn, create_nodeinfo(l, vars, link_functions, node_functions, node_args)
        )
        # The use of AuxiliaryNodeInfo is also to save computation, becasue otherwise, 
        # every time we introduce a new node, we need to check `subsumes` or by all the existing nodes.
        scalarize_then_add_edge!(g, l; lhs_or_rhs=:lhs)
        for r in dependencies[l]
            r_vn = to_varname(r)
            check_and_add_vertex!(
                g, r_vn, create_nodeinfo(r, vars, link_functions, node_functions, node_args)
            )
            add_edge!(g, r_vn, l_vn)
            scalarize_then_add_edge!(g, r; lhs_or_rhs=:rhs)
        end
    end
    check_undeclared_variables(g, vars)
    remove_auxiliary_nodes!(g)
    return g
end

function create_nodeinfo(var::Var, vars, link_functions, node_functions, node_args)
    if var in keys(vars)
        return ConcreteNodeInfo(var, vars, link_functions, node_functions, node_args)
    else
        return AuxiliaryNodeInfo()
    end
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

- `no_transformation_param_length::Int`: The length of the parameters vector without transformation, defining the number of parameters in the model.
- `dynamic_transformation_param_length::Int`: The length of the parameters vector with dynamic transformation.
- `varinfo::SimpleVarInfo`: An instance of 
    [`DynamicPPL.SimpleVarInfo`](https://turinglang.org/DynamicPPL.jl/dev/api/#DynamicPPL.SimpleVarInfo), 
    specifically a dictionary that maps both data and value of variables in the model to the corresponding values.
- `parameters::Vector{VarName}`: A vector containing the names of the parameters in the model. These parameters are defined to be 
    stochastic variables that are not observed.
- `g::BUGSGraph`: An instance of [`BUGSGraph`](@ref), representing the dependency graph of the model.
- `sorted_nodes::Vector{VarName}`: A vector containing the names of all the variables in the model, sorted in topological order.

"""
struct BUGSModel <: AbstractBUGSModel
    no_transformation_param_length::Int
    dynamic_transformation_param_length::Int
    varinfo::SimpleVarInfo
    parameters::Vector{VarName}
    g::BUGSGraph
    sorted_nodes::Vector{VarName}
end

function BUGSModel(g::BUGSGraph, sorted_nodes, vars, array_sizes, data, inits)
    vi = SimpleVarInfo(initialize_var_store(data, vars, array_sizes))
    parameters = VarName[]
    no_transformation_param_length = 0
    dynamic_transformation_param_length = 0
    for vn in sorted_nodes
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
            no_transformation_param_length += length(dist)
            @assert length(dist) == _length(vn) begin
                "length of distribution $dist: $(length(dist)) does not match length of variable $vn: $(_length(vn)), " *
                "please note that if the distribution is a multivariate distribution, " *
                "the left hand side variable should use explicit indexing, e.g. x[1:2] ~ dmnorm(...)."
            end
            dynamic_transformation_param_length += length(Bijectors.transformed(dist))
            isnothing(value) && (value = evaluate(vn, inits))
            if !isnothing(value)
                vi = setindex!!(vi, value, vn)
            else
                vi = setindex!!(vi, rand(dist), vn)
            end
        end
    end
    # TODO: remove after verification
    @assert (isempty(parameters) ? 0 : sum(_length(x) for x in parameters)) ==
        no_transformation_param_length
    return BUGSModel(
        no_transformation_param_length,
        dynamic_transformation_param_length,
        vi,
        parameters,
        g,
        sorted_nodes,
    )
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

function JuliaBUGS.evaluate(vn::VarName, env)
    sym = getsym(vn)
    ret = nothing
    try
        ret = get(env[sym], getlens(vn))
    catch _
    end
    return ismissing(ret) ? nothing : ret
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
    no_transformation_param_length::Int
    dynamic_transformation_param_length::Int
    blanket::Vector{VarName}
    model::BUGSModel
end

function MarkovBlanketCoveredBUGSModel(
    m::BUGSModel, var_group::Union{VarName,Vector{VarName}}; module_under=JuliaBUGS
)
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
    no_transformation_param_length = 0
    dynamic_transformation_param_length = 0
    for vn in m.sorted_nodes
        if vn in blanket_with_vars && !is_logical(m.g[vn])
            dist = eval(module_under, m.g[vn], m.varinfo)
            no_transformation_param_length += length(dist)
            dynamic_transformation_param_length += length(Bijectors.transformed(dist))
        end
    end
    return MarkovBlanketCoveredBUGSModel(
        no_transformation_param_length,
        dynamic_transformation_param_length,
        blanket_with_vars,
        m,
    )
end

transformation(m::BUGSModel) = DynamicPPL.transformation(m.varinfo)
transformation(m::MarkovBlanketCoveredBUGSModel) = transformation(m.model)

get_graph(m::BUGSModel) = m.g
get_graph(m::MarkovBlanketCoveredBUGSModel) = m.model.g

get_varinfo(m::BUGSModel) = m.varinfo
get_varinfo(m::MarkovBlanketCoveredBUGSModel) = m.model.varinfo

function get_param_length(m::Union{BUGSModel,MarkovBlanketCoveredBUGSModel})
    return if transformation(m) isa DynamicPPL.DynamicTransformation
        m.dynamic_transformation_param_length
    else
        m.no_transformation_param_length
    end
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
    AbstractBUGSContext

Abstract type for defining the context in which a BUGS model is evaluated.
"""
abstract type AbstractBUGSContext <: AbstractPPL.AbstractContext end

"""
    assume

Interface function for handling unobserved (latent) variables in the model.
"""
assume

"""
    observe

Interface function for handling observed variables in the model.
"""
observe

"""
    logical_evaluate

Interface function for evaluating logical nodes in the model.
"""
logical_evaluate

function JuliaBUGS.observe(
    ctx::AbstractBUGSContext,
    graph::BUGSGraph,
    vn::VarName,
    vi::SimpleVarInfo;
    transformed=transformation(vi) == DynamicTransformation(),
    module_under=JuliaBUGS,
)
    dist = eval(module_under, graph[vn], vi)
    return acclogp!!(vi, logpdf(dist, vi[vn]))
end

function JuliaBUGS.assume(
    ctx::AbstractBUGSContext,
    graph::BUGSGraph,
    vn::VarName,
    vi::SimpleVarInfo;
    transformed=transformation(vi) == DynamicTransformation(),
    module_under=JuliaBUGS,
)
    dist = eval(module_under, graph[vn], vi)
    if graph[vn].link_function_expr != :identity
        dist = transformed(dist, bijector_of_link_function(link_function_expr))
    end
    value = rand(ctx.rng, dist)
    if transformed
        value_transformed, logabsdetjac = with_logabsdet_jacobian(
            Bijectors.inverse(bijector(dist)), value
        )
        acclogp!!(vi, logpdf(dist, value_transformed) + logabsdetjac)
    else
        acclogp!!(vi, logpdf(dist, value))
    end
    return setindex!!(vi, value, vn)
end

function logical_evaluate(
    ::AbstractBUGSContext,
    graph::BUGSGraph,
    vn::VarName,
    vi::SimpleVarInfo;
    module_under=JuliaBUGS,
)
    return setindex!!(vi, eval(module_under, graph[vn], vi), vn)
end

"""
    DefaultContext

Use values in varinfo to compute the log joint density.
"""
struct DefaultContext <: AbstractBUGSContext end

"""
    SamplingContext

Do an ancestral sampling of the model parameters. Also accumulate log joint density.
"""
struct SamplingContext <: AbstractBUGSContext
    rng::Random.AbstractRNG
end
SamplingContext() = SamplingContext(Random.default_rng())

"""
    LogDensityContext

Use the given values to compute the log joint density.
"""
struct LogDensityContext <: AbstractBUGSContext end

function AbstractPPL.evaluate!!(model::BUGSModel, rng::Random.AbstractRNG)
    return evaluate!!(model, SamplingContext(rng))
end
AbstractPPL.evaluate!!(model::BUGSModel) = AbstractPPL.evaluate!!(model, DefaultContext())

observation_or_assumption(model::BUGSModel, ctx::SamplingContext, vn::VarName) = Assumption
observation_or_assumption(model::BUGSModel, ctx::DefaultContext, vn::VarName) = Observation
function observation_or_assumption(model::BUGSModel, ctx::LogDensityContext, vn::VarName)
    if vn in model.parameters
        Assumption
    else
        Observation
    end
end

function observation_or_assumption(model::MarkovBlanketCoveredBUGSModel, ctx, vn)
    return observation_or_assumption(model.model, ctx, vn)
end

function node_iterator(model::BUGSModel, ctx)
    return model.sorted_nodes
end

function node_iterator(model::MarkovBlanketCoveredBUGSModel, ctx)
    return model.blanket
end

function DynamicPPL.settrans!!(m::BUGSModel, if_trans::Bool)
    return @set m.varinfo = DynamicPPL.settrans!!(m.varinfo, if_trans)
end

function DynamicPPL.settrans!!(m::MarkovBlanketCoveredBUGSModel, if_trans::Bool)
    return @set m.model = DynamicPPL.settrans!!(m.model, if_trans)
end

function AbstractPPL.evaluate!!(
    model::Union{BUGSModel,MarkovBlanketCoveredBUGSModel}, ctx::AbstractBUGSContext
)
    g = get_graph(model)
    vi = deepcopy(get_varinfo(model))
    setlogp!!(vi::SimpleVarInfo, 0)
    for vn in node_iterator(model, ctx)
        if is_logical(g[vn])
            vi = logical_evaluate(ctx, g, vn, vi)
        else
            if observation_or_assumption(model, ctx, vn) == Observation
                vi = observe(ctx, g, vn, vi)
            else
                vi = assume(ctx, g, vn, vi)
            end
        end
    end
    return vi
end

function AbstractPPL.evaluate!!(
    model::Union{BUGSModel,MarkovBlanketCoveredBUGSModel},
    ctx::LogDensityContext,
    flattened_values::AbstractVector;
    module_under=JuliaBUGS,
)
    if_transformed = transformation(model.varinfo) == DynamicTransformation()
    param_length = if if_transformed
        model.dynamic_transformation_param_length
    else
        model.no_transformation_param_length
    end
    @assert length(flattened_values) == param_length
    g = get_graph(model)
    vi = deepcopy(get_varinfo(model))
    vi = setlogp!!(vi, 0)
    current_idx = 1
    for vn in node_iterator(model, ctx)
        if is_logical(g[vn])
            vi = logical_evaluate(ctx, g, vn, vi)
        else
            dist = eval(module_under, g[vn], vi)
            if_non_trivial_link_function = g[vn].link_function_expr != :identity
            if if_non_trivial_link_function
                dist = transformed(dist, bijector_of_link_function(link_function_expr))
            end
            if observation_or_assumption(model, ctx, vn) == Assumption
                if if_transformed
                    l = length(transformed(dist))
                    # value = DynamicPPL.invlink_and_reconstruct(
                    #     dist, flattened_values[current_idx:(current_idx + l - 1)]
                    # )
                    
                    # value_transformed, logabsdetjac = with_logabsdet_jacobian(
                    #     Bijectors.inverse(bijector(dist)), value
                    # )
                    f = DynamicPPL.invlink_transform(dist)
                    value, logjac = DynamicPPL.with_logabsdet_jacobian_and_reconstruct(f, dist, flattened_values[current_idx:(current_idx + l - 1)])
                    current_idx += l
                    
                    vi = acclogp!!(vi, logpdf(dist, value) + logjac)
                else
                    l = length(dist)
                    value = reconstruct(
                        dist, flattened_values[current_idx:(current_idx + l - 1)]
                    )
                    current_idx += l
                    if if_non_trivial_link_function
                        value = invlink(dist, value)
                    end
                    vi = acclogp!!(vi, logpdf(dist, value))
                end
                vi = setindex!!(vi, value, vn)
            else
                vi = acclogp!!(vi, logpdf(dist, vi[vn]))
            end
        end
    end
    return vi
end
