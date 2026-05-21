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
`logpdf(d, nt)` overlays the supplied values into the evaluation environment
and returns the log joint density in the original (constrained) parameter
space.

# Example
```julia
model_def = @bugs begin
    x ~ Normal(0, 1)
    y ~ Normal(x, 1)
end
model = compile(model_def, (; y = 1.0))
d = to_distribution(model)
nt = rand(d)             # (x = ...,)
logpdf(d, nt)
```
"""
function to_distribution(model::BUGSModel)
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

# Promote across parameter distributions to a single ValueSupport.
function _bugs_param_value_support(model::BUGSModel)
    gd = model.graph_evaluation_data
    supports = Distributions.ValueSupport[]
    for i in eachindex(gd.sorted_nodes)
        gd.is_stochastic_vals[i] || continue
        gd.is_observed_vals[i] && continue
        dist = Base.invokelatest(
            gd.node_function_vals[i], model.evaluation_env, gd.loop_vars_vals[i]
        )
        push!(supports, Distributions.value_support(typeof(dist))())
    end
    isempty(supports) && return Distributions.Continuous
    return mapreduce(typeof, promote_type, supports)
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

function Distributions.logpdf(d::BUGSModelDistribution{names}, x::NamedTuple) where {names}
    model = d.model
    env = model.evaluation_env
    for s in names
        haskey(x, s) || throw(ArgumentError("logpdf: missing field $s in NamedTuple input"))
        env = BangBang.setindex!!(env, getfield(x, s), s)
    end
    _, log_densities = evaluate_with_env!!(model, env; transformed=false)
    return log_densities.tempered_logjoint
end

Distributions.pdf(d::BUGSModelDistribution, x::NamedTuple) = exp(Distributions.logpdf(d, x))

function Distributions.loglikelihood(d::BUGSModelDistribution, x::NamedTuple)
    return Distributions.logpdf(d, x)
end
function Distributions.loglikelihood(
    d::BUGSModelDistribution, xs::AbstractArray{<:NamedTuple}
)
    return sum(Base.Fix1(Distributions.logpdf, d), xs)
end
