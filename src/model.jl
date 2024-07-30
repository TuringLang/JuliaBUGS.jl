# AbstractBUGSModel cannot subtype `AbstractPPL.AbstractProbabilisticProgram` (which subtypes `AbstractMCMC.AbstractModel`)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

"""
    BUGSModel

The `BUGSModel` object is used for inference and represents the output of compilation. It implements the
[`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl) interface.
"""
struct BUGSModel{base_model_T<:Union{<:AbstractBUGSModel,Nothing}} <: AbstractBUGSModel
    " Indicates whether the model parameters are in the transformed space. "
    transformed::Bool

    " The length of the parameters vector in the original space. "
    untransformed_param_length::Int
    " The length of the parameters vector in the transformed space. "
    transformed_param_length::Int
    " A dictionary mapping the names of the variables to their lengths in the original space. "
    untransformed_var_lengths::Dict{<:VarName,Int}
    " A dictionary mapping the names of the variables to their lengths in the transformed space. "
    transformed_var_lengths::Dict{<:VarName,Int}

    " An instance of `DynamicPPL.SimpleVarInfo`, which is a dictionary-like data structure that maps both data and values of variables in the model to the corresponding values. "
    varinfo::SimpleVarInfo
    " A vector containing the names of the parameters in the model, defined as stochastic variables that are not observed. This vector should be consistent with `sorted_nodes`. "
    parameters::Vector{<:VarName}
    " A vector containing the names of all the variables in the model, sorted in topological order. In the case of a conditioned model, `sorted_nodes` include all the variables in `parameters` and the variables in the Markov blanket of `parameters`. "
    sorted_nodes::Vector{<:VarName}

    " An instance of `BUGSGraph`, representing the dependency graph of the model. "
    g::BUGSGraph

    " If not `Nothing`, the model is a conditioned model; otherwise, it's the model returned by `compile`. "
    base_model::base_model_T
end

function Base.show(io::IO, m::BUGSModel)
    if m.transformed
        println(
            io,
            "BUGSModel (transformed, with dimension $(m.transformed_param_length)):",
            "\n",
        )
    else
        println(
            io,
            "BUGSModel (untransformed, with dimension $(m.untransformed_param_length)):",
            "\n",
        )
    end
    println(io, "  Parameters of the model:")
    println(io, "    ", join(m.parameters, ", "), "\n")
    println(io, "  Values:")
    return println(io, "$(m.varinfo.values)")
end

"""
    parameters(m::BUGSModel)

Return a vector of `VarName` containing the names of the parameters in the model.
"""
parameters(m::BUGSModel) = m.parameters

"""
    variables(m::BUGSModel)

Return a vector of `VarName` containing the names of all the variables in the model.
"""
variables(m::BUGSModel) = collect(labels(m.g))

function prepare_arg_values(
    args::Tuple{Vararg{Symbol}}, vi::SimpleVarInfo, loop_vars::NamedTuple{lvars}
) where {lvars}
    return NamedTuple{args}(Tuple(
        map(args) do arg
            if arg in lvars
                loop_vars[arg]
            else
                vi[@varname($arg)]
            end
        end,
    ))
end

function BUGSModel(
    g::BUGSGraph,
    vi::SimpleVarInfo,
    initial_params::NamedTuple=NamedTuple();
    is_transformed::Bool=true,
)
    sorted_nodes = VarName[label_for(g, node) for node in topological_sort(g)]
    parameters = VarName[]
    untransformed_param_length, transformed_param_length = 0, 0
    untransformed_var_lengths, transformed_var_lengths = Dict{VarName,Int}(),
    Dict{VarName,Int}()

    for vn in sorted_nodes
        (; is_stochastic, is_observed, node_function, node_args, loop_vars) = g[vn]
        args = prepare_arg_values(node_args, vi, loop_vars)
        if !is_stochastic
            value = Base.invokelatest(node_function; args...)
            vi = setindex!!(vi, value, vn)
        elseif !is_observed
            push!(parameters, vn)
            dist = Base.invokelatest(node_function; args...)

            untransformed_var_lengths[vn] = length(dist)
            # not all distributions are defined for `Bijectors.transformed`
            transformed_var_lengths[vn] = if bijector(dist) == identity
                untransformed_var_lengths[vn]
            else
                length(Bijectors.transformed(dist))
            end
            untransformed_param_length += untransformed_var_lengths[vn]
            transformed_param_length += transformed_var_lengths[vn]

            initialization = try
                AbstractPPL.get(initial_params, vn)
            catch _
                missing
            end
            if !ismissing(initialization)
                vi = setindex!!(vi, initialization, vn)
            else
                init_value = try
                    rand(dist)
                catch e
                    error(
                        "Failed to sample from the prior distribution of $vn, consider providing initialization values for $vn or it's parents: $(collect(MetaGraphsNext.inneighbor_labels(g, vn))...).",
                    )
                end
                vi = setindex!!(vi, init_value, vn)
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
        parameters,
        sorted_nodes,
        g,
        nothing,
    )
end

"""
    initialize!(model::BUGSModel, initial_params::NamedTuple)

Initialize the model with a NamedTuple of initial values, the values are expected to be in the original space.
"""
function initialize!(model::BUGSModel, initial_params::NamedTuple)
    check_input(initial_params)
    for vn in model.sorted_nodes
        (; is_stochastic, is_observed, node_function, node_args, loop_vars) = model.g[vn]
        args = prepare_arg_values(node_args, model.varinfo, loop_vars)
        if !is_stochastic
            value = Base.invokelatest(node_function; args...)
            BangBang.@set!! model.varinfo = setindex!!(model.varinfo, value, vn)
        elseif !is_observed
            initialization = try
                AbstractPPL.get(initial_params, vn)
            catch _
                missing
            end
            if !ismissing(initialization)
                BangBang.@set!! model.varinfo = setindex!!(
                    model.varinfo, initialization, vn
                )
            else
                BangBang.@set!! model.varinfo = setindex!!(
                    model.varinfo, rand(Base.invokelatest(node_function; args...)), vn
                )
            end
        end
    end
    return model
end

"""
    initialize!(model::BUGSModel, initial_params::AbstractVector)

Initialize the model with a vector of initial values, the values can be in transformed space if `model.transformed` is set to true.
"""
function initialize!(model::BUGSModel, initial_params::AbstractVector)
    vi, logp = AbstractPPL.evaluate!!(model, LogDensityContext(), initial_params)
    return BUGSModel(
        model.transformed,
        model.untransformed_param_length,
        model.transformed_param_length,
        model.untransformed_var_lengths,
        model.transformed_var_lengths,
        DynamicPPL.setlogp!!(vi, logp),
        model.parameters,
        model.sorted_nodes,
        model.g,
        model.base_model,
    )
end

"""
    get_params_varinfo(model::BUGSModel[, vi::SimpleVarInfo])

Returns a `SimpleVarInfo` object containing only the parameter values of the model.
If `vi` is provided, it will be used; otherwise, `model.varinfo` will be used.
"""
function get_params_varinfo(model::BUGSModel)
    return get_params_varinfo(model, model.varinfo)
end
function get_params_varinfo(model::BUGSModel, vi::SimpleVarInfo)
    if !model.transformed
        d = Dict{VarName,Any}()
        for param in model.parameters
            d[param] = vi[param]
        end
        return SimpleVarInfo(d, vi.logp, DynamicPPL.NoTransformation())
    else
        d = Dict{VarName,Any}()
        g = model.g
        for v in model.sorted_nodes
            (; is_stochastic, node_function, node_args, loop_vars) = g[v]
            if v in model.parameters
                args = prepare_arg_values(node_args, vi, loop_vars)
                dist = node_function(; args...)
                linked_val = DynamicPPL.link(dist, vi[v])
                d[v] = linked_val
            end
        end
        return SimpleVarInfo(d, vi.logp, DynamicPPL.DynamicTransformation())
    end
end

"""
    getparams(model::BUGSModel[, vi::SimpleVarInfo]; transformed::Bool=false)

Extract the parameter values from the model as a flattened vector, ordered topologically.
If `transformed` is set to true, the parameters are provided in the transformed space.
"""
function getparams(model::BUGSModel; transformed::Bool=false)
    return getparams(model, model.varinfo; transformed=transformed)
end
function getparams(model::BUGSModel, vi::SimpleVarInfo; transformed::Bool=false)
    param_vals = Vector{Float64}(
        undef,
        transformed ? model.transformed_param_length : model.untransformed_param_length,
    )
    pos = 1
    for v in model.parameters
        if !transformed
            val = vi[v]
            len = model.untransformed_var_lengths[v]
            if val isa AbstractArray
                param_vals[pos:(pos + len - 1)] .= vec(val)
            else
                param_vals[pos] = val
            end
        else
            (; node_function, node_args, loop_vars) = model.g[v]
            args = prepare_arg_values(node_args, vi, loop_vars)
            dist = node_function(; args...)
            linked_val = Bijectors.link(dist, vi[v])
            len = model.transformed_var_lengths[v]
            if linked_val isa AbstractArray
                param_vals[pos:(pos + len - 1)] .= vec(linked_val)
            else
                param_vals[pos] = linked_val
            end
        end
        pos += len
    end
    return param_vals
end

"""
    setparams!!(model::BUGSModel, flattened_values::AbstractVector; transformed::Bool=false)

Update the parameter values of a `BUGSModel` with new values provided in a flattened vector.

Only the parameter values are updated, the values of logical variables are kept unchanged.

This function adopts the `BangBang` convention, i.e. it modifies the model in place when possible.

# Arguments
- `m::BUGSModel`: The model to update.
- `flattened_values::AbstractVector`: A vector containing the new parameter values in a flattened form.
- `transformed::Bool=false`: Indicates whether the values in `flattened_values` are in the transformed space.

# Returns
`SimpleVarInfo`: The updated `varinfo` with the new parameter values set.
"""
function setparams!!(
    model::BUGSModel, flattened_values::AbstractVector; transformed::Bool=false
)
    pos = 1
    vi = model.varinfo
    for v in model.parameters
        (; node_function, node_args, loop_vars) = model.g[v]
        args = prepare_arg_values(node_args, vi, loop_vars)
        dist = node_function(; args...)

        len = if transformed
            model.transformed_var_lengths[v]
        else
            model.untransformed_var_lengths[v]
        end
        if transformed
            linked_vals = flattened_values[pos:(pos + len - 1)]
            sample_val = DynamicPPL.invlink_and_reconstruct(dist, linked_vals)
        else
            sample_val = flattened_values[pos:(pos + len - 1)]
        end
        vi = DynamicPPL.setindex!!(vi, sample_val, v)
        pos += len
    end
    return vi
end

function (model::BUGSModel)()
    vi, _ = evaluate!!(model, SamplingContext())
    return get_params_varinfo(model, vi)
end

function settrans(model::BUGSModel, bool::Bool=!(model.transformed))
    return BangBang.setproperty!!(model, :transformed, bool)
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
        new_parameters,
        sorted_blanket_with_vars,
        model.g,
        base_model,
    )
end

function check_var_group(var_group::Vector{<:VarName}, model::BUGSModel)
    non_vars = filter(var -> var ∉ labels(model.g), var_group)
    logical_vars = filter(var -> !model.g[var].is_stochastic, var_group)
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
        (; is_stochastic, node_function, node_args, loop_vars) = g[vn]
        args = prepare_arg_values(node_args, vi, loop_vars)
        if !is_stochastic
            value = node_function(; args...)
            vi = setindex!!(vi, value, vn)
        else
            dist = node_function(; args...)
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
    (; sorted_nodes, g, varinfo) = model
    vi = deepcopy(varinfo)
    logp = 0.0
    for vn in sorted_nodes
        (; is_stochastic, node_function, node_args, loop_vars) = g[vn]
        args = prepare_arg_values(node_args, vi, loop_vars)
        if !is_stochastic
            value = node_function(; args...)
            vi = setindex!!(vi, value, vn)
        else
            dist = node_function(; args...)
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
    param_lengths = if model.transformed
        model.transformed_param_length
    else
        model.untransformed_param_length
    end

    if length(flattened_values) != param_lengths
        error(
            "The length of `flattened_values` does not match the length of the parameters in the model",
        )
    end

    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end

    sorted_nodes = model.sorted_nodes
    g = model.g
    vi = deepcopy(model.varinfo)
    current_idx = 1
    logp = 0.0
    for vn in sorted_nodes
        (; is_stochastic, node_function, node_args, loop_vars) = g[vn]
        args = prepare_arg_values(node_args, vi, loop_vars)
        if !is_stochastic
            value = node_function(; args...)
            vi = setindex!!(vi, value, vn)
        else
            dist = node_function(; args...)
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

"""
    generate_expr(model::BUGSModel)

Generate a Julia function that takes a NamedTuple represent the env and 
vector of parameter values, returns the computed log density.

# Examples
```julia-repl
julia > model_def = @bugs begin
    x[1:2] ~ dmnorm(zeros(2), eye[1:2, 1:2])
    y ~ dnorm(x[1], 1)
    u[1] ~ dnorm(x[2], 1)
    w = y + u[1]
    u[2] ~ dnorm(w, 1)
end
quote
    x[1:2] ~ dmnorm(zeros(2), eye[1:2, 1:2])
    y ~ dnorm(x[1], 1)
    u[1] ~ dnorm(x[2], 1)
    w = y + u[1]
    u[2] ~ dnorm(w, 1)
end

julia> model = compile(model_def, (; x=[1.0, 2.0], eye=[1 0; 0 1]))
BUGSModel (transformed, with dimension 3):

  Parameters of the model:
    u[1], y, u[2]

  Values:
(w = 1.8684132156092446, y = 0.7687440709366652, u = [1.0996691446725793, 2.2946374552395965], eye = [1 0; 0 1], x = [1.0, 2.0])

julia> generate_expr(model)
:(function (var"##value_nt#260", var"##params#261")
      var"##logp#256" = 0.0
      (; w, y, u, eye, x) = var"##value_nt#260"
      var"##dist#257" = (JuliaBUGS.var"#165#167"())(x = x)
      var"##val_and_logjac#258" = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(JuliaBUGS.Bijectors.inverse(JuliaBUGS.Bijectors.bijector(var"##dist#257")), var"##dist#257", var"##params#261"[1:(1 + 1) - 1])
      u[1] = var"##val_and_logjac#258"[1]
      var"##logp#256" = var"##logp#256" + logpdf(var"##dist#257", u[1]) + var"##val_and_logjac#258"[2]
      var"##dist#257" = (JuliaBUGS.var"#162#164"())(x = x)
      var"##val_and_logjac#258" = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(JuliaBUGS.Bijectors.inverse(JuliaBUGS.Bijectors.bijector(var"##dist#257")), var"##dist#257", var"##params#261"[2:(2 + 1) - 1])
      y = var"##val_and_logjac#258"[1]
      var"##logp#256" = var"##logp#256" + logpdf(var"##dist#257", y) + var"##val_and_logjac#258"[2]
      w = (JuliaBUGS.var"#168#170"())(y = y, u = u)
      var"##dist#257" = (JuliaBUGS.var"#171#173"())(w = w)
      var"##val_and_logjac#258" = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(JuliaBUGS.Bijectors.inverse(JuliaBUGS.Bijectors.bijector(var"##dist#257")), var"##dist#257", var"##params#261"[3:(3 + 1) - 1])
      u[2] = var"##val_and_logjac#258"[1]
      var"##logp#256" = var"##logp#256" + logpdf(var"##dist#257", u[2]) + var"##val_and_logjac#258"[2]
      var"##logp#256" = var"##logp#256" + logpdf((JuliaBUGS.var"#159#161"())(eye = eye), x[1:2])
      return var"##logp#256"
  end)
```
"""
function generate_expr(model::BUGSModel)
    # gensyms for intermediate variables to avoid name conflicts with user-defined variables
    _logp = gensym(:logp)
    _dist = gensym(:dist)
    _val_and_logjac = gensym(:val_and_logjac)
    _value_nt = gensym(:value_nt)
    _params = gensym(:params)

    # start with an empty function body
    expr = Expr(:block)
    push!(expr.args, :($_logp = 0.0))
    # unpack the values from the env(NamedTuple)
    push!(
        expr.args,
        Expr(
            :(=),
            Expr(:tuple, Expr(:parameters, collect(keys(model.varinfo.values))...)),
            _value_nt,
        ),
    )
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end
    current_idx = 1
    for vn in model.sorted_nodes
        vn_expr = get_vn_expr(vn)
        (; is_stochastic, is_observed, node_function, node_args, loop_vars) = model.g[vn]
        if !is_stochastic
            # if the node is not stochastic, just eval and bind
            push!(
                expr.args,
                Expr(
                    :(=),
                    vn_expr,
                    generate_function_call_expr(node_function, node_args, loop_vars),
                ),
            )
        else
            if is_observed
                # accumulate the log density of the observed node
                push!(
                    expr.args,
                    Expr(
                        :(=),
                        _logp,
                        Expr(
                            :call,
                            :+,
                            _logp,
                            Expr(
                                :call,
                                :(JuliaBUGS.Distributions.logpdf),
                                generate_function_call_expr(
                                    node_function, node_args, loop_vars
                                ),
                                vn_expr,
                            ),
                        ),
                    ),
                )
            else
                # if the variable is stochastic but not observed, first eval the distribution, then fetch values from the params vector
                push!(
                    expr.args,
                    Expr(
                        :(=),
                        _dist,
                        generate_function_call_expr(node_function, node_args, loop_vars),
                    ),
                )
                l = var_lengths[vn]
                if model.transformed
                    push!(
                        expr.args,
                        :(
                            $_val_and_logjac = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(
                                JuliaBUGS.Bijectors.inverse(
                                    JuliaBUGS.Bijectors.bijector($_dist)
                                ),
                                $_dist,
                                $_params[($current_idx):($current_idx + $l - 1)],
                            )
                        ),
                    )
                    push!(expr.args, :($vn_expr = $_val_and_logjac[1]))
                    push!(
                        expr.args,
                        :(
                            $_logp =
                                $_logp +
                                JuliaBUGS.Distributions.logpdf($_dist, $vn_expr) +
                                $_val_and_logjac[2]
                        ),
                    )
                else
                    push!(
                        expr.args,
                        :(
                            $vn_expr = JuliaBUGS.DynamicPPL.reconstruct(
                                $_dist, $_params[($current_idx):($current_idx + $l - 1)]
                            )
                        ),
                    )
                    push!(expr.args, :($_logp = $_logp + logpdf($_dist, $vn_expr)))
                end
                current_idx += l
            end
        end
    end

    push!(expr.args, :(return $_logp))

    return Expr(:function, Expr(:tuple, _value_nt, _params), expr)
end

"""
    get_vn_expr(vn::VarName)

Generate a Julia expression for the variable name.

# Examples

```jldoctest
julia> JuliaBUGS.get_vn_expr(@varname(a))
:a

julia> JuliaBUGS.get_vn_expr(@varname(a.b))
Symbol("a.b")

julia> JuliaBUGS.get_vn_expr(@varname(a[1]))
:(a[1])

julia> JuliaBUGS.get_vn_expr(@varname(var"a.b"[1]))
:(var"a.b"[1])
```
"""
function get_vn_expr(vn::VarName)
    vn_string = string(Symbol(vn))
    # if there is a . in the string, like "a.b" (R style name), then wrap in var"a.b"
    if occursin(".", vn_string)
        # if a array index, only wrap the array name
        if occursin("[", vn_string)
            array_name, index = split(vn_string, "["; limit=2)
            vn_string = "var\"$(array_name)\"[$(index)"
        else
            vn_string = "var\"$vn_string\""
        end
    end
    return Meta.parse(vn_string)
end

function generate_function_call_expr(node_function, node_args, loop_vars)
    return Expr(
        :call,
        node_function,
        [
            Expr(
                :kw,
                node_arg,
                if node_arg in keys(loop_vars)
                    loop_vars[node_arg]
                else
                    node_arg
                end,
            ) for node_arg in node_args
        ]...,
    )
end
