"""
    BUGSModelDistribution{names,M,S,T} <: Distribution{NamedTupleVariate{names},S}

A `Distributions.Distribution` view of a `BUGSModel`. The variate is a `NamedTuple`
keyed by the (unique) parameter symbols of the underlying model.

Construct via [`to_distribution`](@ref). Sampling and `logpdf` operate in the
model's original (constrained) parameter space — `rand` returns a `NamedTuple`
holding one entry per parameter symbol, taking the value from the evaluation
environment after ancestral sampling, and `logpdf` accepts the same shape.
"""
struct BUGSModelDistribution{names,M<:BUGSModel,S<:Distributions.ValueSupport,T} <:
       Distributions.Distribution{Distributions.NamedTupleVariate{names},S}
    model::M
end

"""
    to_distribution(model::BUGSModel)

Wrap a [`BUGSModel`](@ref) as a `Distributions.Distribution` over `NamedTuple`s.

The returned distribution's variate type is `NamedTupleVariate{names}`, where
`names` are the unique symbols of the model parameters (in graph evaluation
order). `rand(d)` performs ancestral sampling and returns a `NamedTuple` whose
fields are the corresponding entries of the model evaluation environment.
`logpdf(d, nt)` overlays the supplied free-parameter values into the evaluation
environment and returns the log joint density in the original (constrained)
parameter space.

The wrapper always operates in the model's original (constrained) parameter
space: `model.transformed` is ignored and **no log-abs-det-Jacobian is added**,
so the returned density is a constrained-space density and is not, on its own, a
correct unconstrained-space (e.g. HMC) target. It also always uses graph
evaluation (`UseGraph`) and ignores `model.evaluation_mode`, so for a
marginalized model it can differ from `LogDensityProblems.logdensity`.

`logpdf` returns the full joint (prior plus likelihood of any observed data
baked into the model). The observed data is part of the distribution's
**identity**: two models that differ only in their observed data are different
`BUGSModelDistribution`s. Only the model's *free parameters* are read from the
supplied `NamedTuple`, each addressed by its `VarName`; **observed and
deterministic entries in the input are ignored** and taken from the model instead
— observed slots hold the baked-in data, and deterministic nodes are functions of
the parameters and are recomputed. For a partially-observed array this means
`logpdf` is invariant to whatever you place in the observed slots:
`logpdf(d, (x = [999.0, …],))` equals `logpdf(d, (x = [<data>, …],))`. Pass a
full-shaped array (as `rand` returns); only the free-parameter slots affect the
result.

!!! warning
    Tweaking an observed (or deterministic) slot is **inert** — it cannot change
    the result. To score the model against *different* observed data you must
    `compile` a new model and wrap it again; you cannot do it by changing the
    values you pass to `logpdf`. This mirrors DynamicPPL's
    `logjoint`/`loglikelihood(model, params)`, which likewise source observed
    values from the model, not from `params`.

`loglikelihood(d, x)` is an alias for this joint `logpdf`, not a data-only
likelihood. For a model that mixes discrete and continuous parameters the value
support reduces to `Continuous`.

# Example
```julia
model_def = @bugs begin
    x ~ dnorm(0, 1)
    y ~ dnorm(x, 1)
end
model = compile(model_def, (; y = 1.0))
d = to_distribution(model)
nt = rand(d)             # (x = ...,)
logpdf(d, nt)
```
"""
function to_distribution(model::BUGSModel)
    if !(model.evaluation_mode isa UseGraph)
        @warn(
            "to_distribution ignores `model.evaluation_mode` " *
                "($(nameof(typeof(model.evaluation_mode)))) and always uses graph " *
                "evaluation; its `logpdf` may differ from `LogDensityProblems.logdensity` " *
                "for this (e.g. marginalized) model.",
            maxlog = 1,
        )
    end
    syms = Symbol[]
    for vn in parameters(model)
        s = AbstractPPL.getsym(vn)
        s in syms || push!(syms, s)
    end
    names = (syms...,)
    S = _bugs_param_value_support(model)
    eltypes = _bugs_param_nt_eltype(model, names)
    return BUGSModelDistribution{names,typeof(model),S,eltypes}(model)
end

function _bugs_param_value_support(model::BUGSModel)
    gd = model.graph_evaluation_data
    support_types = Type{<:Distributions.ValueSupport}[]
    for i in eachindex(gd.sorted_nodes)
        gd.is_stochastic_vals[i] || continue
        gd.is_observed_vals[i] && continue
        dist = Base.invokelatest(
            gd.node_function_vals[i], model.evaluation_env, gd.loop_vars_vals[i]
        )
        push!(support_types, Distributions.value_support(typeof(dist)))
    end
    isempty(support_types) && return Distributions.Continuous
    return reduce(promote_type, support_types)
end

# Recover the NamedTuple eltype from the current evaluation environment.
function _bugs_param_nt_eltype(model::BUGSModel, names::Tuple{Vararg{Symbol}})
    env = model.evaluation_env
    Ts = ntuple(i -> typeof(getfield(env, names[i])), length(names))
    return NamedTuple{names,Tuple{Ts...}}
end

Base.eltype(::Type{<:BUGSModelDistribution{<:Any,<:Any,<:Any,T}}) where {T} = T

function Base.show(io::IO, d::BUGSModelDistribution{names}) where {names}
    print(io, "BUGSModelDistribution{", names, "}(…)")
    return nothing
end

function Random.rand(rng::Random.AbstractRNG, d::BUGSModelDistribution{names}) where {names}
    evaluation_env, _ = evaluate_with_rng!!(rng, d.model; transformed=false)
    return NamedTuple{names}(map(s -> getfield(evaluation_env, s), names))
end

# Random.rand has no built-in array fallback for `Distribution{NamedTupleVariate}`, so it
# would recurse to a `StackOverflowError`. Provide an explicit `dims`-form that draws
# scalar samples eagerly.
function Base.rand(
    rng::Random.AbstractRNG, d::BUGSModelDistribution{names}, dims::Dims
) where {names}
    out = Array{eltype(d)}(undef, dims)
    for i in eachindex(out)
        out[i] = rand(rng, d)
    end
    return out
end

function Distributions._rand!(
    rng::Random.AbstractRNG, d::BUGSModelDistribution, xs::AbstractArray
)
    for i in eachindex(xs)
        xs[i] = rand(rng, d)
    end
    return xs
end

function Distributions.logpdf(d::BUGSModelDistribution, x::NamedTuple)
    model = d.model
    # Overlay onto an isolated copy (NOT model.evaluation_env): passing the live env
    # would bypass evaluate_with_env!!'s default smart-copy and mutate the model's
    # deterministic array nodes in place, so logpdf would have observable side effects.
    env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)
    # Overlay only the *free parameters*, each addressed by its `VarName` optic. Observed and
    # deterministic entries are deliberately NOT read from `x`: observed data is already baked
    # into `env`, and deterministic nodes are recomputed during evaluation. Overlaying a whole
    # top-level symbol instead (e.g. `setindex!!(env, x.x, :x)`) would clobber the observed
    # slots of a partially-observed array, making the density depend on the values the caller
    # supplied for those slots rather than on the model's data.
    for vn in parameters(model)
        AbstractPPL.hasvalue(x, vn) || throw(
            ArgumentError("logpdf: missing value for parameter `$vn` in NamedTuple input"),
        )
        env = BangBang.setindex!!(env, AbstractPPL.getvalue(x, vn), vn)
    end
    _, log_densities = evaluate_with_env!!(model, env; transformed=false)
    # Untempered joint = logprior + loglikelihood, independent of any temperature default.
    return log_densities.logprior + log_densities.loglikelihood
end

Distributions.pdf(d::BUGSModelDistribution, x::NamedTuple) = exp(Distributions.logpdf(d, x))

function Distributions.loglikelihood(d::BUGSModelDistribution, x::NamedTuple)
    return Distributions.logpdf(d, x)
end
function Distributions.loglikelihood(
    d::BUGSModelDistribution, xs::AbstractArray{<:NamedTuple}
)
    return sum(Base.Fix1(Distributions.logpdf, d), xs; init=0.0)
end
