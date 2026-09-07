"""
    BUGSMarginalDistribution{M<:BUGSModel,D<:AbstractDict} <: Distributions.ContinuousMultivariateDistribution

The continuous parameters of a `BUGSModel` as one distribution, with every discrete parameter summed out by [`UseAutoMarginalization`](@ref).

Construct with [`to_marginal`](@ref).
The variate is the vector of constrained values of the continuous parameters, in the order of `model.marginalization_cache.continuous_model_parameters`.
`logpdf` is the marginal log joint of the compiled model at those values, prior and likelihood of the baked-in data included, as a density in constrained space.
`rand` draws the whole model ancestrally and returns the continuous parameters.
[`recover_discrete`](@ref) draws the summed-out latents back for a given value.
"""
struct BUGSMarginalDistribution{M<:BUGSModel,D<:AbstractDict} <:
       Distributions.ContinuousMultivariateDistribution
    model::M
    constrained_offsets::D
    constrained_length::Int
end

function BUGSMarginalDistribution(model::BUGSModel)
    params = _marginal_params(model)
    offsets = Dict{eltype(params),Int}()
    offset = 1
    for vn in params
        offsets[vn] = offset
        offset += model.untransformed_var_lengths[vn]
    end
    return BUGSMarginalDistribution(model, offsets, offset - 1)
end

_marginal_params(model::BUGSModel) = model.marginalization_cache.continuous_model_parameters

"""
    to_marginal(model::BUGSModel)
    to_marginal(source::AbstractString; data, replace_period=true, no_enclosure=false)

Wrap a BUGS model as a [`BUGSMarginalDistribution`](@ref) over its continuous parameters, with every discrete parameter marginalized out.

The model is switched to the transformed space and to [`UseAutoMarginalization`](@ref), so the same restrictions apply: only discrete parameters with finite support can be summed out, and a `dpois` or other unbounded discrete parameter is an error.

The string form parses BUGS source the way `@bugs` does and compiles it against `data`.
Identical calls return the cached distribution, so the source can be written where it is used.
With DynamicPPL loaded the result can stand on the right-hand side of `~`, where the left-hand side receives the constrained continuous parameters.

# Example
```julia
d = to_marginal(\"\"\"
model {
  for (i in 1:N) {
    z[i] ~ dcat(w[1:2])
    y[i] ~ dnorm(mu[z[i]], 1)
  }
  for (k in 1:2) { mu[k] ~ dnorm(0, 0.01) }
}
\"\"\"; data = (; N = 3, w = [0.5, 0.5], y = [-3.0, 3.1, -2.9]))
x = rand(d)          # the two means, in constrained space
logpdf(d, x)         # log p(mu, y) with z summed out
```
"""
function to_marginal(model::BUGSModel)
    model.transformed || (model = settrans(model, true))
    if !(model.evaluation_mode isa UseAutoMarginalization)
        unbounded = _unbounded_discrete_parameters(model)
        if !isempty(unbounded)
            throw(
                ArgumentError(
                    "to_marginal sums out discrete parameters with finite support only, " *
                    "and $(join(string.(unbounded), ", ")) $(length(unbounded) == 1 ? "has" : "have") unbounded support",
                ),
            )
        end
        model = set_evaluation_mode(model, UseAutoMarginalization())
        # `set_evaluation_mode` warns and falls back to `UseGraph` when it cannot build
        # the marginalization, which here has to be an error.
        model.evaluation_mode isa UseAutoMarginalization || throw(
            ArgumentError("JuliaBUGS could not build the marginalization for this model"),
        )
    end
    return BUGSMarginalDistribution(model)
end

function _unbounded_discrete_parameters(model::BUGSModel)
    gd = model.graph_evaluation_data
    node_types = JuliaBUGS.Model._compute_node_types(model)
    index = Dict(gd.sorted_nodes[i] => i for i in eachindex(gd.sorted_nodes))
    return [
        vn for vn in gd.model_parameters if
        haskey(index, vn) && node_types[index[vn]] == :discrete_infinite
    ]
end

const _MARGINAL_CACHE = Dict{Any,BUGSMarginalDistribution}()
const _MARGINAL_CACHE_LOCK = ReentrantLock()

function to_marginal(
    source::AbstractString; data, replace_period::Bool=true, no_enclosure::Bool=false
)
    key = (String(source), data, replace_period, no_enclosure)
    return lock(_MARGINAL_CACHE_LOCK) do
        get!(_MARGINAL_CACHE, key) do
            model_def = JuliaBUGS.Parser._bugs_string_input(
                String(source), replace_period, no_enclosure
            )
            to_marginal(JuliaBUGS.compile(model_def, data))
        end
    end
end

Base.length(d::BUGSMarginalDistribution) = d.constrained_length

_flat(x::Number) = [x]
_flat(x::AbstractArray) = vec(x)

_cat(parts, T) = isempty(parts) ? zeros(T, 0) : reduce(vcat, parts)

# The marginal log joint in unconstrained space, Jacobian included, straight from the
# evaluator. `LogDensityProblems.logdensity` wraps the same call in a `try`, which
# reverse-mode AD cannot differentiate through.
function _marginal_logdensity(model::BUGSModel, u::AbstractVector{<:Real})
    _, log_densities = evaluate_with_marginalization_values!!(model, u)
    return log_densities.tempered_logjoint
end

# The continuous parameters as one constrained vector, read from an environment.
function _read_constrained(d::BUGSMarginalDistribution, env)
    parts = [_flat(AbstractPPL.getvalue(env, vn)) for vn in _marginal_params(d.model)]
    return _cat(parts, Float64)
end

"""
    _constrain(d, u)

Map an unconstrained vector to the constrained continuous parameters.
"""
function _constrain(d::BUGSMarginalDistribution, u::AbstractVector{<:Real})
    env, _ = evaluate!!(d.model, u)
    parts = [_flat(AbstractPPL.getvalue(env, vn)) for vn in _marginal_params(d.model)]
    return _cat(parts, eltype(u))
end

"""
    _constrain_with_logjac(d, u)

Map an unconstrained vector to the constrained continuous parameters and return the log absolute determinant of that map's Jacobian alongside.
"""
function _constrain_with_logjac(d::BUGSMarginalDistribution, u::AbstractVector{<:Real})
    model = d.model
    mc = model.marginalization_cache
    env, _ = evaluate!!(model, u)
    parts = Any[]
    logjac = zero(eltype(u))
    for vn in _marginal_params(model)
        (; node_function, loop_vars) = model.g[vn]
        dist = node_function(env, loop_vars)
        b_inv = Bijectors.inverse(Bijectors.bijector(dist))
        offset = mc.param_offsets[vn]
        slice = view(u, offset:(offset + mc.param_lengths[vn] - 1))
        x, lj = Bijectors.with_logabsdet_jacobian(b_inv, reconstruct(b_inv, dist, slice))
        push!(parts, _flat(x))
        logjac += lj
    end
    return _cat(parts, eltype(u)), logjac
end

"""
    _unconstrain_with_logjac(d, x)

Map constrained continuous parameters to the unconstrained vector the model evaluates, and return the log absolute determinant of that map's Jacobian alongside.

The deterministic nodes are recomputed on the way, so a parameter whose support depends on another parameter gets the bijector for the values in `x`.
Returns `nothing` when a value lies outside its support.
"""
function _unconstrain_with_logjac(d::BUGSMarginalDistribution, x::AbstractVector{<:Real})
    model = d.model
    gd = model.graph_evaluation_data
    env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)
    for (i, vn) in enumerate(gd.sorted_nodes)
        if !gd.is_stochastic_vals[i]
            value = gd.node_function_vals[i](env, gd.loop_vars_vals[i])
            env = setindex!!(env, value, vn)
        elseif haskey(d.constrained_offsets, vn)
            offset = d.constrained_offsets[vn]
            len = model.untransformed_var_lengths[vn]
            current = AbstractPPL.getvalue(env, vn)
            value = if current isa AbstractArray
                reshape(x[offset:(offset + len - 1)], size(current))
            else
                x[offset]
            end
            env = setindex!!(env, value, vn)
        end
    end
    parts = Any[]
    logjac = zero(eltype(x))
    for vn in _marginal_params(model)
        (; node_function, loop_vars) = model.g[vn]
        dist = node_function(env, loop_vars)
        value = AbstractPPL.getvalue(env, vn)
        Distributions.insupport(dist, value) || return nothing
        u, lj = Bijectors.with_logabsdet_jacobian(Bijectors.bijector(dist), value)
        push!(parts, _flat(u))
        logjac += lj
    end
    u = _cat(parts, eltype(x))
    return all(isfinite, u) ? (u, logjac) : nothing
end

function _unconstrain(d::BUGSMarginalDistribution, x::AbstractVector{<:Real})
    result = _unconstrain_with_logjac(d, x)
    result === nothing &&
        throw(ArgumentError("a value lies outside its parameter's support"))
    return first(result)
end

function Distributions.insupport(d::BUGSMarginalDistribution, x::AbstractVector{<:Real})
    return length(x) == length(d) && _unconstrain_with_logjac(d, x) !== nothing
end

function Distributions.logpdf(d::BUGSMarginalDistribution, x::AbstractVector{<:Real})
    if length(x) != length(d)
        throw(DimensionMismatch("expected $(length(d)) values, got $(length(x))"))
    end
    result = _unconstrain_with_logjac(d, x)
    result === nothing && return float(eltype(x))(-Inf)
    u, logjac = result
    # The marginal log density is stated in unconstrained space with its Jacobian
    # included, and `logjac` here is that of the inverse map, so adding it undoes it.
    return _marginal_logdensity(d.model, u) + logjac
end

function Distributions._rand!(
    rng::Random.AbstractRNG, d::BUGSMarginalDistribution, x::AbstractVector{<:Real}
)
    env, _ = evaluate_with_rng!!(rng, d.model)
    x .= _read_constrained(d, env)
    return x
end

"""
    recover_discrete([rng,] d::BUGSMarginalDistribution, x::AbstractVector{<:Real})

Draw the marginalized discrete latents from their conditional posterior `p(z | θ, y)` at the continuous parameters `x`, and forward-sample the generated quantities after them.

Returns the model's evaluation environment holding those draws alongside `x` and the data.
This is what a Stan `generated quantities` block does for a marginalized model, and it uses the same recovery as sampling into a chain.
"""
function recover_discrete(
    rng::Random.AbstractRNG, d::BUGSMarginalDistribution, x::AbstractVector{<:Real}
)
    env, _ = evaluate!!(d.model, _unconstrain(d, x))
    return forward_sample_generated_quantities!!(rng, d.model, env)
end
function recover_discrete(d::BUGSMarginalDistribution, x::AbstractVector{<:Real})
    return recover_discrete(Random.default_rng(), d, x)
end
