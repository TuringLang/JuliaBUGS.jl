# AbstractBUGSModel can't be a subtype of AbstractProbabilisticProgram (<: AbstractMCMC.AbstractModel)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

"""
    BUGSModel

The `BUGSModel` object is used for inference and represents the output of compilation. It fully implements the
[`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl) interface.

# Fields

- `param_length::Int`: The length of the parameters vector, defining the number of parameters in the model, store a tuple of integers,
    where the first integer is the length of the parameters vector in the original space, and the second integer is the length of the 
    parameters vector in the transformed space.
- `var_lengths::Dict{VarName,Tuple{Int,Int}}`: A dictionary that maps the names of the variables in the model to the corresponding
    lengths of the variables in the original space and the transformed space.
- `varinfo::SimpleVarInfo`: An instance of 
    [`DynamicPPL.SimpleVarInfo`](https://turinglang.org/DynamicPPL.jl/dev/api/#DynamicPPL.SimpleVarInfo), 
    specifically a dictionary that maps both data and value of variables in the model to the corresponding values.
- `parameters::Vector{VarName}`: A vector containing the names of the parameters in the model. These parameters are defined to be 
    stochastic variables that are not observed.
- `g::BUGSGraph`: An instance of [`BUGSGraph`](@ref), representing the dependency graph of the model.
- `sorted_nodes::Vector{VarName}`: A vector containing the names of all the variables in the model, sorted in topological order.

"""
struct BUGSModel <: AbstractBUGSModel
    transformed::Bool

    untransformed_param_length::Int
    transformed_param_length::Int
    untransformed_var_lengths::Dict{VarName,Int}
    transformed_var_lengths::Dict{VarName,Int} # TODO: store this as a delta from `untransformed_var_lengths`?

    varinfo::SimpleVarInfo
    parameters::Vector{VarName}
    sorted_nodes::Vector{VarName} # sorted_nodes contains all the variables we're going to visit, in conditioned model, this is the markov blanket

    g::BUGSGraph
    base_model::Union{BUGSModel,Nothing} # if not Nothing, then the model is a conditioned model; otherwise, it's the model returned by `compile`
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

function BUGSModel(
    g::BUGSGraph,
    sorted_nodes::Vector{<:VarName},
    vars,
    array_sizes,
    data,
    inits;
    is_transformed::Bool=true,
)
    vs = initialize_var_store(data, vars, array_sizes)
    vi = SimpleVarInfo(vs)
    parameters = VarName[]
    untransformed_param_length = 0
    transformed_param_length = 0
    untransformed_var_lengths = Dict{VarName,Int}()
    transformed_var_lengths = Dict{VarName,Int}()
    for vn in sorted_nodes
        @assert !(g[vn] isa AuxiliaryNodeInfo) "Auxiliary nodes should not be in the graph, but $(g[vn]) is."

        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
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
            value = evaluate(vn, data) # `evaluate(::VarName, env)` is defined in `src/utils.jl`
            if value isa Nothing # not observed
                push!(parameters, vn)
                this_param_length = length(dist)
                untransformed_param_length += this_param_length

                @assert length(dist) == _length(vn) begin
                    "The dimensionality of distribution $dist: $(length(dist)) does not match length of variable $vn: $(_length(vn)), " *
                    "please note that if the distribution is a multivariate distribution, " *
                    "the left hand side variable should use explicit indexing, e.g. x[1:2] ~ dmnorm(...)."
                end
                if bijector(dist) == identity
                    this_param_transformed_length = this_param_length
                else
                    this_param_transformed_length = length(Bijectors.transformed(dist))
                end
                untransformed_var_lengths[vn] = this_param_length
                transformed_var_lengths[vn] = this_param_transformed_length
                transformed_param_length += this_param_transformed_length
                value = evaluate(vn, inits) # use inits to initialize the value if available
                if value isa Nothing # not initialized
                    vi = setindex!!(vi, rand(dist), vn)
                else
                    vi = setindex!!(vi, value, vn)
                end
            else
                vi = setindex!!(vi, value, vn)
            end
        end
    end
    @assert (isempty(parameters) ? 0 : sum(_length(x) for x in parameters)) ==
        untransformed_param_length "$(isempty(parameters) ? 0 : sum(_length(x) for x in parameters)) $untransformed_param_length"
    return BUGSModel(
        is_transformed,
        untransformed_param_length,
        transformed_param_length,
        untransformed_var_lengths,
        transformed_var_lengths,
        vi,
        parameters,
        sorted_nodes,
        g,
        nothing,
    )
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
    get_params_varinfo(m::BUGSModel[, vi::SimpleVarInfo])

Returns a `SimpleVarInfo` object containing only the parameter values of the model.
If `vi` is provided, it will be used; otherwise, `m.varinfo` will be used.
"""
function get_params_varinfo(m::BUGSModel)
    return get_params_varinfo(m, m.varinfo)
end
function get_params_varinfo(m::BUGSModel, vi::SimpleVarInfo)
    if !m.transformed
        d = Dict{VarName,Any}()
        for param in m.parameters
            d[param] = vi[param]
        end
        return SimpleVarInfo(d, vi.logp, DynamicPPL.NoTransformation())
    else
        d = Dict{VarName,Any}()
        g = m.g
        for vn in m.sorted_nodes
            ni = g[vn]
            @unpack node_type, node_function_expr, node_args = ni
            args = Dict(getsym(arg) => vi[arg] for arg in node_args)
            expr = node_function_expr.args[2]
            if vn in m.parameters
                dist = _eval(expr, args)
                linked_val = DynamicPPL.link(dist, vi[vn])
                d[vn] = linked_val
            end
        end
        return SimpleVarInfo(d, vi.logp, DynamicPPL.DynamicTransformation())
    end
end

# TODO: add this function to `ADgradient` with `ReverseDiff` when compiled
# see https://github.com/TuringLang/Turing.jl/pull/2097
# TODO: a static allocated version is possible because we know the size, but not worth the complexity now
"""
    getparams(m::BUGSModel[, vi::SimpleVarInfo], transformed::Bool=false)

Return the values of the parameters in the model as a vector, the values are flattened 
in the order of `m.parameters` (also the topological order). If `transformed` is true,
the parameters are returned in their transformed space.
"""
function getparams(m::BUGSModel; transformed::Bool=false)
    return getparams(m, m.varinfo; transformed=transformed)
end
function getparams(m::BUGSModel, vi::SimpleVarInfo; transformed::Bool=false)
    if !transformed
        params_vi = get_params_varinfo(m, vi)
        return vcat(
            [
                isa(params_vi[p], Real) ? params_vi[p] : vec(params_vi[p]) for
                p in m.parameters
            ]...,
        )
    else
        transformed_param_vals = Vector{Float64}(undef, m.transformed_param_length)
        pos = 1
        for v in m.parameters
            ni = m.g[v]
            args = (; (getsym(arg) => vi[arg] for arg in ni.node_args)...)
            dist = _eval(ni.node_function_expr.args[2], args)

            link_vals = Bijectors.link(dist, vi[v])
            len = m.transformed_var_lengths[v]
            transformed_param_vals[pos:(pos + len - 1)] .= link_vals
            pos += len
        end
        return transformed_param_vals
    end
end

# only set the parameter values, the values of logical nodes are not updated
function setparams!!(
    m::BUGSModel, flattened_values::AbstractVector; transformed::Bool=false
)
    pos = 1
    vi = m.varinfo
    for v in m.parameters
        ni = m.g[v]
        args = (; (getsym(arg) => vi[arg] for arg in ni.node_args)...)
        dist = _eval(ni.node_function_expr.args[2], args)

        len = if transformed
            m.transformed_var_lengths[v]
        else
            m.untransformed_var_lengths[v]
        end
        if transformed
            link_vals = flattened_values[pos:(pos + len - 1)]
            sample_val = DynamicPPL.invlink_and_reconstruct(dist, link_vals)
        else
            sample_val = flattened_values[pos:(pos + len - 1)]
        end
        vi = DynamicPPL.setindex!!(vi, sample_val, v)
        pos += len
    end
    return vi
end

# TODO: For now, a varinfo contains all model parameters is returned; alternatively, can return the generated quantities
function (model::BUGSModel)()
    vi, logp = evaluate!!(model, SamplingContext())
    return get_params_varinfo(model, vi)
end

function settrans(model::BUGSModel, bool::Bool=!(model.transformed))
    return @set model.transformed = bool
end

function AbstractPPL.condition(
    model::BUGSModel,
    d::Dict{<:VarName,<:Any},
    sorted_nodes=Nothing, # support cached sorted Markov blanket nodes
)
    return AbstractPPL.condition(
        model, collect(keys(d)), update_varinfo(model.varinfo, d); sorted_nodes=sorted_nodes
    )
end

function AbstractPPL.condition(
    model::BUGSModel,
    var_group::Vector{<:VarName},
    varinfo=model.varinfo,
    sorted_nodes=Nothing,
)
    check_var_group(var_group, model)
    base_model = model.base_model isa Nothing ? model : model.base_model
    new_parameters = setdiff(model.parameters, var_group)

    sorted_blanket_with_vars = if sorted_nodes isa Nothing
        sorted_nodes
    else
        filter(
            vn -> vn in union(markov_blanket(model.g, new_parameters), new_parameters),
            model.sorted_nodes,
        )
    end

    return BUGSModel(
        model.transformed,
        sum(model.untransformed_var_lengths[v] for v in new_parameters),
        sum(model.transformed_var_lengths[v] for v in new_parameters),
        model.untransformed_var_lengths,
        model.transformed_var_lengths,
        varinfo,
        new_parameters,
        sorted_blanket_with_vars,
        model.g,
        base_model,
    )
end

function AbstractPPL.decondition(model::BUGSModel, var_group::Vector{<:VarName})
    check_var_group(var_group, model)
    base_model = model.base_model isa Nothing ? model : model.base_model

    new_parameters = union(model.parameters, var_group)

    @show new_parameters markov_blanket(model.g, new_parameters)
    sorted_blanket_with_vars = filter(
        vn -> vn in union(markov_blanket(model.g, new_parameters)), base_model.sorted_nodes
    )
    return BUGSModel(
        model.transformed,
        sum(model.untransformed_var_lengths[v] for v in new_parameters),
        sum(model.transformed_var_lengths[v] for v in new_parameters),
        model.untransformed_var_lengths,
        model.transformed_var_lengths,
        model.varinfo,
        new_parameters,
        sorted_blanket_with_vars,
        model.g,
        base_model,
    )
end

function check_var_group(var_group::Vector{<:VarName}, model::BUGSModel)
    non_vars = filter(var -> var ∉ labels(model.g), var_group)
    logical_vars = filter(var -> model.g[var].node_type == Logical, var_group)
    isempty(non_vars) || error("Variables $(non_vars) are not in the model")
    return isempty(logical_vars) || error(
        "Variables $(logical_vars) are not stochastic variables, conditioning on them is not supported",
    )
end

function update_varinfo(varinfo::SimpleVarInfo, d::Dict{VarName,<:Any})
    new_varinfo = deepcopy(varinfo)
    for (p, value) in d
        setindex!!(new_varinfo, value, p)
    end
    return new_varinfo
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
    @unpack varinfo, g, sorted_nodes = model
    vi = deepcopy(varinfo)
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            value = rand(ctx.rng, dist) # just sample from the prior
            logp += logpdf(dist, value)
            vi = setindex!!(vi, value, vn)
        end
    end
    return vi, logp
end

function AbstractPPL.evaluate!!(model::BUGSModel)
    return AbstractPPL.evaluate!!(model, DefaultContext())
end
function AbstractPPL.evaluate!!(model::BUGSModel, ::DefaultContext)
    sorted_nodes = model.sorted_nodes
    g = model.g
    vi = deepcopy(model.varinfo)
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical # be conservative -- always propagate values of logical nodes
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            value = vi[vn]
            if model.transformed
                # although the values stored in `vi` are in their original space, 
                # when `DynamicTransformation`, we behave as accepting a vector of 
                # parameters in the transformed space
                value_transformed = transform(bijector(dist), value)
                logp +=
                    logpdf(dist, value) +
                    logabsdetjac(Bijectors.inverse(bijector(dist)), value_transformed)
            else
                logp += logpdf(dist, value)
            end
        end
    end
    return vi, logp
end

function AbstractPPL.evaluate!!(
    model::BUGSModel, ::LogDensityContext, flattened_values::AbstractVector
)
    @assert length(flattened_values) == (
        if model.transformed
            model.transformed_param_length
        else
            model.untransformed_param_length
        end
    )

    var_lengths =
        model.transformed ? model.transformed_var_lengths : model.untransformed_var_lengths
    sorted_nodes = model.sorted_nodes
    g = model.g
    vi = deepcopy(model.varinfo)
    current_idx = 1
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
        args = (; map(arg -> getsym(arg) => vi[arg], node_args)...)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            if vn in model.parameters
                l = var_lengths[vn]
                if model.transformed
                    value, logjac = DynamicPPL.with_logabsdet_jacobian_and_reconstruct(
                        Bijectors.inverse(bijector(dist)),
                        dist,
                        flattened_values[current_idx:(current_idx + l - 1)],
                    )
                else
                    value = DynamicPPL.reconstruct(
                        dist, flattened_values[current_idx:(current_idx + l - 1)]
                    )
                    logjac = 0.0
                end
                current_idx += l
                logp += logpdf(dist, value) + logjac
                vi = setindex!!(vi, value, vn)
            else
                logp += logpdf(dist, vi[vn])
            end
        end
    end
    return vi, logp
end
