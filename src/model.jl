# AbstractBUGSModel can't be a subtype of AbstractProbabilisticProgram (<: AbstractMCMC.AbstractModel)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

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
    vi = DynamicPPL.settrans!!(
        SimpleVarInfo(initialize_var_store(data, vars, array_sizes)), true
    )
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
            if isnothing(value) # not observed
                push!(parameters, vn)
                no_transformation_param_length += length(dist)
                @assert length(dist) == _length(vn) begin
                    "length of distribution $dist: $(length(dist)) does not match length of variable $vn: $(_length(vn)), " *
                    "please note that if the distribution is a multivariate distribution, " *
                    "the left hand side variable should use explicit indexing, e.g. x[1:2] ~ dmnorm(...)."
                end
                if bijector(dist) == identity
                    dynamic_transformation_param_length += length(dist)
                else
                    dynamic_transformation_param_length += length(
                        Bijectors.transformed(dist)
                    )
                end
                value = evaluate(vn, inits) # use inits to initialize the value if available
                if !isnothing(value)
                    vi = setindex!!(vi, value, vn)
                else
                    vi = setindex!!(vi, rand(dist), vn)
                end
            else
                vi = setindex!!(vi, value, vn) # observed
            end
        end
    end
    @assert (isempty(parameters) ? 0 : sum(_length(x) for x in parameters)) ==
        no_transformation_param_length "$(isempty(parameters) ? 0 : sum(_length(x) for x in parameters)) $no_transformation_param_length"
    return BUGSModel(
        no_transformation_param_length,
        dynamic_transformation_param_length,
        vi,
        parameters,
        g,
        sorted_nodes,
    )
end

get_graph(m::BUGSModel) = m.g

transformation(m::BUGSModel) = DynamicPPL.transformation(m.varinfo)

get_varinfo(m::BUGSModel) = m.varinfo

function node_iterator(model::BUGSModel, ctx)
    return model.sorted_nodes
end

function DynamicPPL.settrans!!(m::BUGSModel, if_trans::Bool)
    return @set m.varinfo = DynamicPPL.settrans!!(m.varinfo, if_trans)
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

""" 
    get_params_varinfo(m::BUGSModel[, vi::SimpleVarInfo])

Return the `SimpleVarInfo` object that contains the parameters in the model. If `vi` is not provided,
use values from `vi` to create the returned `SimpleVarInfo` object.
"""
function get_params_varinfo(m::BUGSModel)
    return get_params_varinfo(m, m.varinfo)
end
function get_params_varinfo(
    m::BUGSModel,
    vi::SimpleVarInfo,
    if_transformed=vi.transformation == DynamicTransformation(),
)
    d = Dict{VarName,Any}()
    for vn in m.parameters
        value = m.varinfo[vn]
        if if_transformed
            dist = JuliaBUGS.eval(m.g[vn], m.varinfo)
            value = transform(bijector(dist), value)
        end
        d[vn] = value
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
        if vn in blanket_with_vars && !is_logical(m.g[vn]) && vn ∈ m.parameters
            dist = eval(module_under, m.g[vn], m.varinfo)
            no_transformation_param_length += length(dist)
            if bijector(dist) == identity
                dynamic_transformation_param_length += length(dist)
            else
                dynamic_transformation_param_length += length(Bijectors.transformed(dist))
            end
        end
    end
    return MarkovBlanketCoveredBUGSModel(
        no_transformation_param_length,
        dynamic_transformation_param_length,
        blanket_with_vars,
        m,
    )
end

transformation(m::MarkovBlanketCoveredBUGSModel) = transformation(m.model)

get_graph(m::MarkovBlanketCoveredBUGSModel) = m.model.g

get_varinfo(m::MarkovBlanketCoveredBUGSModel) = m.model.varinfo

node_iterator(model::MarkovBlanketCoveredBUGSModel, ctx) = model.blanket

"""
    get_param_length(m::Union{BUGSModel,MarkovBlanketCoveredBUGSModel})

Return the length of the model parameters.
"""
function get_param_length(m::Union{BUGSModel,MarkovBlanketCoveredBUGSModel})
    return if transformation(m) isa DynamicPPL.DynamicTransformation
        m.dynamic_transformation_param_length
    else
        m.no_transformation_param_length
    end
end

# Contexts for evaluating BUGS models

"""
    AbstractBUGSContext

Abstract type for defining the context in which a BUGS model is evaluated.
"""
abstract type AbstractBUGSContext <: AbstractPPL.AbstractContext end

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

# Default implementations

# A subtle point about the value of `logp`:
# If `DynamicTransformation`, then we assume the values of the parameters are inverse transformed values,
# so when computing the log joint density, we need to consider the Jacobian of the transformation. 
function JuliaBUGS.observe(
    ctx::AbstractBUGSContext,
    graph::BUGSGraph,
    vn::VarName,
    vi::SimpleVarInfo;
    if_transformed=transformation(vi) == DynamicTransformation(),
    module_under=JuliaBUGS,
)
    dist = eval(module_under, graph[vn], vi)
    value = vi[vn]
    if if_transformed
        acclogp!!(
            vi,
            logpdf(dist, value) + logabsdetjac(
                DynamicPPL.invlink_transform(dist), transform(bijector(dist), vi[vn])
            ),
        )
    else
        acclogp!!(vi, logpdf(dist, value))
    end
end

function JuliaBUGS.assume(
    ctx::AbstractBUGSContext,
    graph::BUGSGraph,
    vn::VarName,
    vi::SimpleVarInfo;
    if_transformed=transformation(vi) == DynamicTransformation(),
    module_under=JuliaBUGS,
)
    dist = eval(module_under, graph[vn], vi)
    value = rand(ctx.rng, dist)
    acclogp!!(vi, logpdf(dist, value))
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

function AbstractPPL.evaluate!!(model::BUGSModel, rng::Random.AbstractRNG)
    return evaluate!!(model, SamplingContext(rng))
end
AbstractPPL.evaluate!!(model::BUGSModel) = AbstractPPL.evaluate!!(model, DefaultContext())

observation_or_assumption(model::BUGSModel, ctx::DefaultContext, vn::VarName) = Observation
observation_or_assumption(model::BUGSModel, ctx::SamplingContext, vn::VarName) = Assumption
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

function DynamicPPL.settrans!!(m::MarkovBlanketCoveredBUGSModel, if_trans::Bool)
    return @set m.model = DynamicPPL.settrans!!(m.model, if_trans)
end

# `evaluate!!` functions

# Default implementation
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
                vi = JuliaBUGS.observe(ctx, g, vn, vi)
            else
                vi = JuliaBUGS.assume(ctx, g, vn, vi)
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
            if observation_or_assumption(model, ctx, vn) == Assumption
                if if_transformed
                    l = length(transformed(dist))
                    value, logjac = DynamicPPL.with_logabsdet_jacobian_and_reconstruct(
                        DynamicPPL.invlink_transform(dist),
                        dist,
                        flattened_values[current_idx:(current_idx + l - 1)],
                    )
                    current_idx += l
                    vi = setindex!!(vi, value, vn)
                    vi = acclogp!!(vi, logpdf(dist, value) + logjac)
                else
                    l = length(dist)
                    value = reconstruct(
                        dist, flattened_values[current_idx:(current_idx + l - 1)]
                    )
                    current_idx += l
                    vi = setindex!!(vi, value, vn)
                    vi = acclogp!!(vi, logpdf(dist, value))
                end
            else
                vi = acclogp!!(vi, logpdf(dist, vi[vn]))
            end
        end
    end
    return vi
end
