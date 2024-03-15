# AbstractBUGSModel can't be a subtype of AbstractProbabilisticProgram (<: AbstractMCMC.AbstractModel)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

"""
    BUGSModel

The `BUGSModel` object is used for inference and represents the output of compilation. It fully implements the
[`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl) interface.

# Fields

- `transformed::Bool`: Indicates whether the model parameters are in the transformed space.
- `untransformed_param_length::Int`: The length of the parameters vector in the original space.
- `transformed_param_length::Int`: The length of the parameters vector in the transformed space.
- `untransformed_var_lengths::Dict{VarName,Int}`: A dictionary mapping the names of the variables to their lengths in the original space.
- `transformed_var_lengths::Dict{VarName,Int}`: A dictionary mapping the names of the variables to their lengths in the transformed space.
- `varinfo::SimpleVarInfo`: An instance of 
    [`DynamicPPL.SimpleVarInfo`](https://turinglang.org/DynamicPPL.jl/dev/api/#DynamicPPL.SimpleVarInfo), 
    which is a dictionary-like data structure that maps both data and values of variables in the model to the corresponding values.
- `parameters::Vector{VarName}`: A vector containing the names of the parameters in the model, defined as 
    stochastic variables that are not observed. This vector should be consistent with `sorted_nodes`.
- `sorted_nodes::Vector{VarName}`: A vector containing the names of all the variables in the model, sorted in topological order.
    In the case of a conditioned model, `sorted_nodes` include all the variables in `parameters` and the variables in the Markov blanket of `parameters`.
- `g::BUGSGraph`: An instance of [`BUGSGraph`](@ref), representing the dependency graph of the model.
- `base_model::Union{BUGSModel,Nothing}`: If not `Nothing`, the model is a conditioned model; otherwise, it's the model returned by `compile`.

"""
struct BUGSModel <: AbstractBUGSModel
    transformed::Bool

    untransformed_param_length::Int
    transformed_param_length::Int
    untransformed_var_lengths::Dict{VarName,Int}
    transformed_var_lengths::Dict{VarName,Int}

    varinfo::SimpleVarInfo
    distributions::Dict{VarName,Distribution}
    parameters::Vector{VarName}
    sorted_nodes::Vector{VarName}

    g::BUGSGraph

    " The base model if the model is a conditioned model; otherwise, `nothing`. "
    base_model::Union{BUGSModel,Nothing}
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

function BUGSModel(
    g::BUGSGraph, eval_env::NamedTuple, inits::NamedTuple; is_transformed::Bool=true
)
    sorted_nodes = map(topological_sort(g)) do node
        label_for(g, node)
    end
    vs = initialize_var_store(eval_env)
    vi = SimpleVarInfo(vs, 0.0)
    dist_store = Dict{VarName,Distribution}()
    parameters = VarName[]
    untransformed_param_length = 0
    transformed_param_length = 0
    untransformed_var_lengths = Dict{VarName,Int}()
    transformed_var_lengths = Dict{VarName,Int}()
    for vn in sorted_nodes
        (; is_stochastic, is_observed, node_function_expr, node_args, loop_vars) = g[vn]
        args = merge(
            NamedTuple{node_args}(Tuple([vi[@varname($arg)] for arg in node_args])),
            loop_vars,
        )
        expr = node_function_expr.args[2].args[1].args[1]
        if !is_stochastic
            value = _eval(expr, args, dist_store)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args, dist_store)
            dist_store[vn] = dist
            value = try
                AbstractPPL.get(inits, vn)
            catch _
                missing
            end
            if !is_observed
                push!(parameters, vn)
                this_param_length = length(dist)
                untransformed_param_length += this_param_length

                if bijector(dist) == identity
                    this_param_transformed_length = this_param_length
                else
                    this_param_transformed_length = length(Bijectors.transformed(dist))
                end
                untransformed_var_lengths[vn] = this_param_length
                transformed_var_lengths[vn] = this_param_transformed_length
                transformed_param_length += this_param_transformed_length
                if !is_resolved(value) # not initialized
                    vi = setindex!!(vi, rand(dist), vn)
                else
                    vi = setindex!!(vi, value, vn)
                end
            else
                vi = setindex!!(vi, value, vn)
            end
        end
    end
    return BUGSModel(
        is_transformed,
        untransformed_param_length,
        transformed_param_length,
        untransformed_var_lengths,
        transformed_var_lengths,
        vi,
        dist_store,
        parameters,
        sorted_nodes,
        g,
        nothing,
    )
end

function initialize_var_store(eval_env::NamedTuple)
    var_store = Dict{Symbol,Any}()
    for k in keys(eval_env)
        v = eval_env[k]
        if v === missing
            var_store[k] = 0.0
        elseif v isa AbstractArray && Missing <: eltype(v)
            var_store[k] = map(x -> x === missing ? 0.0 : x, v)
        else
            var_store[k] = v
        end
    end
    return NamedTuple(var_store)
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
            (; is_stochastic, is_observed, node_function_expr, node_args, loop_vars) = g[vn]
            args = merge(
                NamedTuple{node_args}(Tuple([vi[@varname($arg)] for arg in node_args])),
                loop_vars,
            )
            expr = node_function_expr.args[2].args[1].args[1]
            if vn in m.parameters
                dist = _eval(expr, args, m.distributions)
                linked_val = DynamicPPL.link(dist, vi[vn])
                d[vn] = linked_val
            end
        end
        return SimpleVarInfo(d, vi.logp, DynamicPPL.DynamicTransformation())
    end
end

"""
    getparams(m::BUGSModel[, vi::SimpleVarInfo]; transformed::Bool=false)

Extract the parameter values from the model as a flattened vector, ordered topologically.
If `transformed` is set to true, the parameters are provided in the transformed space.
"""
function getparams(m::BUGSModel; transformed::Bool=false)
    return getparams(m, m.varinfo; transformed=transformed)
end
function getparams(m::BUGSModel, vi::SimpleVarInfo; transformed::Bool=false)
    if !transformed
        param_vals = Vector{Float64}(undef, m.untransformed_param_length)
        pos = 1
        for p in m.parameters
            val = vi[p]
            len = m.untransformed_var_lengths[p]
            if isa(val, Real)
                param_vals[pos] = val
                pos += 1
            else
                param_vals[pos:(pos + len - 1)] .= vec(val)
                pos += len
            end
        end
        return param_vals
    else
        transformed_param_vals = Vector{Float64}(undef, m.transformed_param_length)
        pos = 1
        for v in m.parameters
            ni = m.g[v]
            args = (; (getsym(arg) => vi[arg] for arg in ni.node_args)...)
            dist = _eval(ni.node_function_expr.args[2], args, m.distributions)

            link_vals = Bijectors.link(dist, vi[v])
            len = m.transformed_var_lengths[v]
            transformed_param_vals[pos:(pos + len - 1)] .= link_vals
            pos += len
        end
        return transformed_param_vals
    end
end

"""
    setparams!!(m::BUGSModel, flattened_values::AbstractVector; transformed::Bool=false)

Update the parameter values of a `BUGSModel` with new values provided in a flattened vector.

Only the parameter values are updated, the values of logical variables are kept unchanged.

This function adopt the bangbang convention, i.e. it modifies the model in place when possible.

# Arguments
- `m::BUGSModel`: The model to update.
- `flattened_values::AbstractVector`: A vector containing the new parameter values in a flattened form.
- `transformed::Bool=false`: Indicates whether the values in `flattened_values` are in the transformed space.

# Returns
`SimpleVarInfo`: The updated `varinfo` with the new parameter values set.
"""
function setparams!!(
    m::BUGSModel, flattened_values::AbstractVector; transformed::Bool=false
)
    pos = 1
    vi = m.varinfo
    for v in m.parameters
        ni = m.g[v]
        args = (; (getsym(arg) => vi[arg] for arg in ni.node_args)...)
        dist = _eval(ni.node_function_expr.args[2], args, m.distributions)

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
    return BangBang.setproperties!!(model, :transformed, bool)
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
        model.distributions,
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
    new_parameters = [v for v in model.sorted_nodes if v in new_parameters] # keep the order

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
        model.distributions,
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
    (; varinfo, g, sorted_nodes) = model
    vi = deepcopy(varinfo)
    logp = 0.0
    for vn in sorted_nodes
        (; is_stochastic, is_observed, node_function_expr, node_args, loop_vars) = g[vn]
        args = merge(
            NamedTuple{node_args}(Tuple([vi[@varname($arg)] for arg in node_args])),
            loop_vars,
        )
        expr = node_function_expr.args[2].args[1].args[1]
        if !is_stochastic
            value = _eval(expr, args, model.distributions)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args, model.distributions)
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
        (; is_stochastic, is_observed, node_function_expr, node_args, loop_vars) = g[vn]
        args = merge(
            NamedTuple{node_args}(Tuple([vi[@varname($arg)] for arg in node_args])),
            loop_vars,
        )
        expr = node_function_expr.args[2].args[1].args[1]
        if !is_stochastic # be conservative -- always propagate values of logical nodes
            value = _eval(expr, args, model.distributions)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args, model.distributions)
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
        (; is_stochastic, is_observed, node_function_expr, node_args, loop_vars) = g[vn]
        args = merge(
            NamedTuple{node_args}(Tuple([vi[@varname($arg)] for arg in node_args])),
            loop_vars,
        )
        expr = node_function_expr.args[2].args[1].args[1]
        if !is_stochastic
            value = _eval(expr, args, model.distributions)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args, model.distributions)
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
