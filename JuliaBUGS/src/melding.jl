"""
    Melding

Markov melding for `BUGSModel`s, after Goudie, Presanis, Lunn, De Angelis and Wernisch,
*Joining and Splitting Models with Markov Melding*, Bayesian Analysis 14(1), 2019.

Several submodels that share a *link* quantity ``\\phi`` are joined into one target density.
Submodel ``m`` has density ``p_m(\\phi, \\psi_m, y_m)`` over the link, its private parameters
``\\psi_m`` and its data ``y_m``, and prior marginal ``p_m(\\phi)`` for the link. The melded
posterior is

```math
p_{\\text{meld}}(\\phi, \\psi_1, \\ldots, \\psi_M \\mid y_1, \\ldots, y_M)
  \\;\\propto\\; p_{\\text{pool}}(\\phi) \\prod_{m=1}^{M} \\frac{p_m(\\phi, \\psi_m, y_m)}{p_m(\\phi)},
```

where ``p_{\\text{pool}}`` is a pooling of the submodel marginals. See [`meld`](@ref) for the
user entry point and the documentation page *Markov Melding* for the derivation and examples.
"""
module Melding

using AbstractMCMC: AbstractMCMC
using AbstractPPL: AbstractPPL, VarName, @varname, condition, fix
using ADTypes: ADTypes
using BangBang: BangBang
using Bijectors: Bijectors
using Distributions
using LinearAlgebra
using LogDensityProblems
using LogExpFunctions: logsumexp
using MetaGraphsNext: labels, inneighbor_labels
using Random
using Statistics

using JuliaBUGS: JuliaBUGS
using JuliaBUGS.Model:
    BUGSModel,
    BUGSGraph,
    FixedParameter,
    GeneratedQuantity,
    ModelParameter,
    Observation,
    TransformedParameter,
    getparams,
    model_parameters,
    smart_copy_evaluation_env,
    variable_type

export meld, MeldedModel, MeldedModelWithGradient
export evaluation_envs, link_value, parameter_names, nsubmodels
export AbstractPooling, ProductOfExperts, Dictatorial, LogarithmicPooling, LinearPooling
export AbstractMarginal, ExactMarginal, SimulatedMarginal, FunctionMarginal, logmarginal

#######################
# Pooling
#######################

"""
    AbstractPooling

A rule ``g`` that combines the submodel prior marginals of the link into the pooled prior
``p_{\\text{pool}}(\\phi) = g(p_1(\\phi), \\ldots, p_M(\\phi))``.

Internally every pooling is expressed through two quantities, so that the melded log density is

```math
\\sum_m \\log p_m(\\phi, \\psi_m, y_m) \\;+\\; \\sum_m a_m \\log p_m(\\phi) \\;+\\; e(\\phi),
```

with per-submodel exponents ``a_m`` from [`marginal_exponents`](@ref) and an extra term
``e`` from [`logpool_extra`](@ref). Only submodels with ``a_m \\neq 0``, or every submodel when
[`needs_all_marginals`](@ref) is `true`, need an [`AbstractMarginal`](@ref).
"""
abstract type AbstractPooling end

"""
    ProductOfExperts()

Product-of-experts pooling, ``p_{\\text{pool}}(\\phi) \\propto \\prod_m p_m(\\phi)``.

Every ``p_m(\\phi)`` cancels, so the melded density is the product of the submodel joints and
no marginal of the link is ever evaluated. The pooled prior is typically more concentrated
than the individual priors, and more so with every submodel added; Goudie et al. call it the
least intuitive rule for that reason.
"""
struct ProductOfExperts <: AbstractPooling end

"""
    Dictatorial(k::Int)

Dictatorial pooling, ``p_{\\text{pool}}(\\phi) = p_k(\\phi)``: submodel `k` keeps its prior on
the link and every other submodel has its own prior on the link divided out.
"""
struct Dictatorial <: AbstractPooling
    dictator::Int
    function Dictatorial(k::Integer)
        k >= 1 || throw(ArgumentError("the dictator index must be positive, got $k"))
        return new(Int(k))
    end
end

"""
    LogarithmicPooling(weights::AbstractVector{<:Real})

Logarithmic pooling, ``p_{\\text{pool}}(\\phi) \\propto \\prod_m p_m(\\phi)^{\\lambda_m}``,
with non-negative weights ``\\lambda_m``. Weights of one for every submodel give
[`ProductOfExperts`](@ref); equal weights ``1/M`` give the geometric mean, whose spread does
not shrink as more submodels are added. The normalising constant of the pooled prior does not
depend on ``\\phi`` and is dropped.
"""
struct LogarithmicPooling{T<:Real} <: AbstractPooling
    weights::Vector{T}
    function LogarithmicPooling(weights::AbstractVector{T}) where {T<:Real}
        all(w -> w >= 0, weights) ||
            throw(ArgumentError("logarithmic pooling weights must be non-negative"))
        return new{T}(collect(weights))
    end
end

"""
    LinearPooling(weights::AbstractVector{<:Real})

Linear pooling, ``p_{\\text{pool}}(\\phi) = \\sum_m \\lambda_m p_m(\\phi)``, a mixture of the
submodel marginals. Weights are normalised to sum to one. Every submodel marginal is needed
and must be a properly normalised density, because the mixture weights only have meaning
when the components are on the same scale.
"""
struct LinearPooling{T<:Real} <: AbstractPooling
    weights::Vector{T}
    function LinearPooling(weights::AbstractVector{<:Real})
        all(w -> w >= 0, weights) ||
            throw(ArgumentError("linear pooling weights must be non-negative"))
        s = sum(weights)
        s > 0 || throw(ArgumentError("linear pooling weights must not all be zero"))
        w = collect(float.(weights) ./ s)
        return new{eltype(w)}(w)
    end
end

function _check_pooling(pooling::AbstractPooling, M::Int)
    return nothing
end
function _check_pooling(pooling::Dictatorial, M::Int)
    pooling.dictator <= M || throw(
        ArgumentError(
            "dictator index $(pooling.dictator) exceeds the number of submodels $M"
        ),
    )
    return nothing
end
function _check_pooling(pooling::Union{LogarithmicPooling,LinearPooling}, M::Int)
    length(pooling.weights) == M || throw(
        ArgumentError(
            "pooling has $(length(pooling.weights)) weights but there are $M submodels"
        ),
    )
    return nothing
end

"""
    marginal_exponents(pooling, M) -> Vector{Float64}

Coefficients ``a_m`` on ``\\log p_m(\\phi)`` in the melded log density, see
[`AbstractPooling`](@ref).
"""
marginal_exponents(::ProductOfExperts, M::Int) = zeros(M)
function marginal_exponents(p::Dictatorial, M::Int)
    a = fill(-1.0, M)
    a[p.dictator] = 0.0
    return a
end
marginal_exponents(p::LogarithmicPooling, M::Int) = float.(p.weights) .- 1.0
marginal_exponents(::LinearPooling, M::Int) = fill(-1.0, M)

"""
    needs_all_marginals(pooling) -> Bool

Whether the extra term of the pooling requires every submodel marginal.
"""
needs_all_marginals(::AbstractPooling) = false
needs_all_marginals(::LinearPooling) = true

"""
    logpool_extra(pooling, logmarginals) -> Real

The term ``e(\\phi)`` of [`AbstractPooling`](@ref), given the vector of
``\\log p_m(\\phi)``. Zero except for [`LinearPooling`](@ref), where it is
``\\log \\sum_m \\lambda_m p_m(\\phi)``.
"""
function logpool_extra(::AbstractPooling, logmarginals)
    return isempty(logmarginals) ? 0.0 : zero(float(first(logmarginals)))
end
function logpool_extra(p::LinearPooling, logmarginals)
    return logsumexp(log.(p.weights) .+ logmarginals)
end

#######################
# Links
#######################

"""
    LinkInfo

How the link quantity appears in one submodel.

- `nodes`: the graph nodes that make up the link, in a fixed order shared across submodels.
- `kind`: `:closed` when every node is unobserved stochastic and every stochastic ancestor
  of a link node is itself a link node, so the prior marginal of the link is exactly the
  product of the link nodes' own factors; `:open` when the nodes are stochastic but have
  stochastic ancestors outside the link; `:logical` when every node is deterministic.
- `shapes`: `size` of each node's value, used to write a flat vector back into the model.
- `length`: total number of scalars in the link.
"""
struct LinkInfo
    nodes::Vector{VarName}
    kind::Symbol
    shapes::Vector{Tuple{Vararg{Int}}}
    length::Int
end

_as_varnames(vn::VarName) = VarName[vn]
_as_varnames(s::Symbol) = VarName[VarName{s}()]
function _as_varnames(xs::Union{AbstractVector,Tuple})
    out = VarName[]
    for x in xs
        append!(out, _as_varnames(x))
    end
    return out
end

# Column-major position of an element node inside its array, so that the element nodes of an
# array are ordered the way `vec` orders the array's values. Nodes that are not single
# elements of an array sort first.
function _linear_index_key(vn::VarName, env::NamedTuple)
    optic = AbstractPPL.getoptic(vn)
    optic isa AbstractPPL.Index || return 0
    arr = env[AbstractPPL.getsym(vn)]
    arr isa AbstractArray || return 0
    all(i -> i isa Integer, optic.ix) && length(optic.ix) == ndims(arr) || return 0
    return LinearIndices(size(arr))[Int.(optic.ix)...]
end

# Resolve the user's link specification to graph nodes. A name that is not itself a node but
# subsumes nodes, such as an array name, expands to those nodes in column-major index order.
function _resolve_link_nodes(model::BUGSModel, spec)
    node_labels = collect(labels(model.g))
    label_set = Set(node_labels)
    resolved = VarName[]
    for vn in _as_varnames(spec)
        if vn in label_set
            push!(resolved, vn)
        else
            subsumed = [l for l in node_labels if AbstractPPL.subsumes(vn, l)]
            isempty(subsumed) &&
                throw(ArgumentError("link variable $vn does not exist in the submodel"))
            sort!(subsumed; by=l -> (_linear_index_key(l, model.evaluation_env), string(l)))
            append!(resolved, subsumed)
        end
    end
    allunique(resolved) ||
        throw(ArgumentError("link specification $(spec) names a node more than once"))
    return resolved
end

# All ancestors of `nodes` in the graph, stochastic and deterministic.
function _ancestors(g::BUGSGraph, nodes::Vector{<:VarName})
    seen = Set{VarName}()
    stack = VarName[]
    for vn in nodes
        append!(stack, inneighbor_labels(g, vn))
    end
    while !isempty(stack)
        v = pop!(stack)
        v in seen && continue
        push!(seen, v)
        append!(stack, inneighbor_labels(g, v))
    end
    return seen
end

function _link_info(model::BUGSModel, spec)
    nodes = _resolve_link_nodes(model, spec)
    g = model.g
    for vn in nodes
        info = g[vn]
        info.is_observed && throw(
            ArgumentError(
                "link node $vn is observed in a submodel; a link must be a parameter"
            ),
        )
        variable_type(model, vn) == FixedParameter && throw(
            ArgumentError("link node $vn is already fixed in a submodel; unfix it first"),
        )
    end
    stochastic = [g[vn].is_stochastic for vn in nodes]
    kind = if all(stochastic)
        anc = _ancestors(g, nodes)
        outside = [v for v in anc if g[v].is_stochastic && !(v in nodes)]
        isempty(outside) ? :closed : :open
    elseif !any(stochastic)
        :logical
    else
        throw(
            ArgumentError(
                "the link nodes of one submodel must be all stochastic or all logical, " *
                "got a mixture: $(nodes)",
            ),
        )
    end
    shapes = Tuple{Vararg{Int}}[
        size(AbstractPPL.getvalue(model.evaluation_env, vn)) for vn in nodes
    ]
    len = sum(prod, shapes; init=0)
    return LinkInfo(nodes, kind, shapes, len)
end

# Flatten the link values stored in `env` into a vector.
function _read_link(env::NamedTuple, info::LinkInfo)
    parts = map(info.nodes) do vn
        v = AbstractPPL.getvalue(env, vn)
        v isa AbstractArray ? vec(v) : [v]
    end
    return reduce(vcat, parts)
end

# Write a flat link vector into a copy of `env`. Array-valued link nodes are copied first so
# the model's own environment is never mutated.
function _write_link(env::NamedTuple, info::LinkInfo, φ::AbstractVector)
    length(φ) == info.length ||
        throw(DimensionMismatch("link has $(info.length) scalars but got $(length(φ))"))
    copied = Set{Symbol}()
    pos = 1
    for (vn, shape) in zip(info.nodes, info.shapes)
        sym = AbstractPPL.getsym(vn)
        if env[sym] isa AbstractArray && !(sym in copied)
            env = BangBang.setindex!!(env, copy(env[sym]), sym)
            push!(copied, sym)
        end
        n = prod(shape)
        value = if isempty(shape)
            φ[pos]
        else
            reshape(collect(view(φ, pos:(pos + n - 1))), shape)
        end
        env = BangBang.setindex!!(env, value, vn)
        pos += n
    end
    return env
end

#######################
# Marginals
#######################

"""
    AbstractMarginal

The prior marginal density ``p_m(\\phi)`` of the link under one submodel, evaluated through
[`logmarginal`](@ref) on the original (constrained) scale of the link.
"""
abstract type AbstractMarginal end

"""
    logmarginal(marginal::AbstractMarginal, φ::AbstractVector{<:Real}) -> Real

Log prior marginal density of the link at the flat link vector `φ`, on the constrained
scale, with no Jacobian term.
"""
function logmarginal end

"""
    ExactMarginal(model::BUGSModel, link)

The exact prior marginal of a *closed* link: every link node is stochastic and every
stochastic ancestor of a link node is itself a link node. The marginal is then the product
of the link nodes' own factors, ``\\prod_{v \\in \\phi} p(v \\mid \\mathrm{pa}(v))``, read off the
graph with no integration and no estimate. Deterministic ancestors of the link are
recomputed from constants and link values.

Throws an `ArgumentError` when the link is not closed.
"""
struct ExactMarginal{M<:BUGSModel} <: AbstractMarginal
    model::M
    info::LinkInfo
    needed::Vector{Int}   # indices into sorted_nodes, topological order
end

function ExactMarginal(model::BUGSModel, link)
    info = link isa LinkInfo ? link : _link_info(model, link)
    info.kind == :closed || throw(
        ArgumentError(
            "ExactMarginal needs a closed stochastic link; link $(info.nodes) is $(info.kind). " *
            "Supply a SimulatedMarginal or FunctionMarginal for this submodel instead.",
        ),
    )
    node_set = Set(info.nodes)
    anc = _ancestors(model.g, info.nodes)
    sorted_nodes = model.graph_evaluation_data.sorted_nodes
    needed = [i for (i, vn) in enumerate(sorted_nodes) if vn in node_set || vn in anc]
    return ExactMarginal(model, info, needed)
end

function logmarginal(em::ExactMarginal, φ::AbstractVector{<:Real})
    model = em.model
    gd = model.graph_evaluation_data
    env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)
    env = _write_link(env, em.info, φ)
    lp = zero(float(eltype(φ)))
    for i in em.needed
        vn = gd.sorted_nodes[i]
        node_function = gd.node_function_vals[i]
        loop_vars = gd.loop_vars_vals[i]
        if !gd.is_stochastic_vals[i]
            env = BangBang.setindex!!(env, node_function(env, loop_vars), vn)
        else
            dist = node_function(env, loop_vars)
            lp += logpdf(dist, AbstractPPL.getvalue(env, vn))
        end
    end
    return lp
end

"""
    FunctionMarginal(f)

A user-supplied log prior marginal of the link. `f` receives the link value on its
constrained scale, as a scalar when the link has one element and as a vector otherwise, and
returns the log density. Use this when the marginal is known analytically or has been fitted
elsewhere.
"""
struct FunctionMarginal{F} <: AbstractMarginal
    f::F
end

function logmarginal(fm::FunctionMarginal, φ::AbstractVector{<:Real})
    return length(φ) == 1 ? fm.f(φ[1]) : fm.f(φ)
end

"""
    GaussianKDE

A product-Gaussian kernel density estimate on an unconstrained scale, used by
[`SimulatedMarginal`](@ref). Stores the points as a `d × n` matrix and one bandwidth per
dimension.
"""
struct GaussianKDE{T<:Real}
    points::Matrix{T}
    bandwidth::Vector{T}
end

function GaussianKDE(points::AbstractMatrix{<:Real}; bandwidth=nothing)
    d, n = size(points)
    n >= 2 || throw(ArgumentError("a kernel density estimate needs at least two points"))
    h = if bandwidth === nothing
        # Scott's rule, per dimension.
        [max(std(view(points, j, :)), eps()) * n^(-1 / (d + 4)) for j in 1:d]
    elseif bandwidth isa Real
        fill(float(bandwidth), d)
    else
        collect(float.(bandwidth))
    end
    length(h) == d ||
        throw(ArgumentError("bandwidth has $(length(h)) entries for $d dimensions"))
    T = promote_type(float(eltype(points)), eltype(h))
    return GaussianKDE{T}(Matrix{T}(points), Vector{T}(h))
end

function _logpdf(k::GaussianKDE, z::AbstractVector{<:Real})
    d, n = size(k.points)
    length(z) == d || throw(DimensionMismatch("point has length $(length(z)), expected $d"))
    lognorm = -sum(log, k.bandwidth) - d * log(2π) / 2 - log(n)
    terms = map(1:n) do i
        s = zero(promote_type(eltype(z), eltype(k.points)))
        for j in 1:d
            u = (z[j] - k.points[j, i]) / k.bandwidth[j]
            s -= u * u / 2
        end
        s
    end
    return logsumexp(terms) + lognorm
end

_logpdf(d::Distribution, z::AbstractVector{<:Real}) = logpdf(d, z)
_logpdf(d::UnivariateDistribution, z::AbstractVector{<:Real}) = logpdf(d, only(z))

"""
    SimulatedMarginal(model::BUGSModel, link; n=10_000, rng=Random.default_rng(),
                      transform=identity, estimator=:kde, bandwidth=nothing)

Estimate the prior marginal of the link under `model` by prior simulation. `n` draws are
taken from the prior of `model` by ancestral sampling (observed nodes keep their data
values, which JuliaBUGS treats as constants of the model), the link is read off each draw,
mapped through `transform` to an unconstrained scale, and a density is fitted there. The estimated
marginal on the constrained scale includes the Jacobian of `transform`.

- `transform`: `identity`, a univariate function with a `with_logabsdet_jacobian` method such
  as `log` applied elementwise, or any `Bijectors` transform. Use `log` for a positive link
  and `Bijectors.Logit(0, 1)` for a probability.
- `estimator`: `:kde` for a product-Gaussian kernel density estimate with Scott's bandwidth,
  or `:normal` for a Gaussian fit (`Normal` or `MvNormal`) to the transformed draws.
- `bandwidth`: a scalar or per-dimension override for the kernel bandwidth.

The estimate sits in a denominator of the melded density, so its tails matter. Check it
against the exact marginal whenever one is available, prefer `:normal` when the transformed
draws look Gaussian, and increase `n` when they do not.

    SimulatedMarginal(draws::AbstractMatrix; transform=identity, estimator=:kde, bandwidth=nothing)

Fit the same estimate from a `d × n` matrix of link draws on the constrained scale, for
example draws produced elsewhere.
"""
struct SimulatedMarginal{B,D} <: AbstractMarginal
    transform::B
    density::D
    n::Int
end

_as_transform(::typeof(identity)) = identity
_as_transform(b::Bijectors.Transform) = b
_as_transform(f::Function) = Bijectors.elementwise(f)

function _transform_with_jac(::typeof(identity), φ::AbstractVector)
    return φ, zero(float(eltype(φ)))
end
function _transform_with_jac(b, φ::AbstractVector)
    z, lj = Bijectors.with_logabsdet_jacobian(b, φ)
    return z, lj
end

function SimulatedMarginal(
    draws::AbstractMatrix{<:Real};
    transform=identity,
    estimator::Symbol=:kde,
    bandwidth=nothing,
)
    d, n = size(draws)
    b = _as_transform(transform)
    Z = Matrix{Float64}(undef, d, n)
    support_error = ArgumentError(
        "transformed link draws contain non-finite values; check that `transform` " *
        "matches the support of the link",
    )
    for i in 1:n
        z = try
            first(_transform_with_jac(b, Vector{Float64}(view(draws, :, i))))
        catch e
            e isa DomainError && throw(support_error)
            rethrow(e)
        end
        Z[:, i] = z
    end
    all(isfinite, Z) || throw(support_error)
    density = if estimator == :kde
        GaussianKDE(Z; bandwidth=bandwidth)
    elseif estimator == :normal
        if d == 1
            fit(Normal, vec(Z))
        else
            MvNormal(vec(mean(Z; dims=2)), Symmetric(cov(Z; dims=2)))
        end
    else
        throw(ArgumentError("unknown estimator $(estimator); use :kde or :normal"))
    end
    return SimulatedMarginal(b, density, n)
end

function SimulatedMarginal(
    model::BUGSModel,
    link;
    n::Integer=10_000,
    rng::Random.AbstractRNG=Random.default_rng(),
    transform=identity,
    estimator::Symbol=:kde,
    bandwidth=nothing,
)
    info = link isa LinkInfo ? link : _link_info(model, link)
    draws = Matrix{Float64}(undef, info.length, n)
    for i in 1:n
        draws[:, i] = _read_link(rand(rng, model), info)
    end
    return SimulatedMarginal(draws; transform, estimator, bandwidth)
end

function logmarginal(sm::SimulatedMarginal, φ::AbstractVector{<:Real})
    z, lj = _transform_with_jac(sm.transform, φ)
    return _logpdf(sm.density, z) + lj
end

_as_marginal(m::AbstractMarginal) = m
_as_marginal(f::Function) = FunctionMarginal(f)
_as_marginal(d::Distribution) = FunctionMarginal(x -> logpdf(d, x))

#######################
# The melded model
#######################

"""
    MeldedModel

The Markov melded target built by [`meld`](@ref). It implements the `LogDensityProblems`
interface over the concatenation of the prepared submodels' parameter vectors, in submodel
order, each block in that submodel's own parameterisation (transformed when the submodel is).

# Fields
- `submodels`: the submodels as passed to `meld`.
- `prepared`: the submodels as evaluated: the carrier unchanged, the others with the link
  fixed or conditioned.
- `roles`: `:carrier`, `:fixed` or `:conditioned` per submodel.
- `links`: a [`LinkInfo`](@ref) per submodel.
- `carrier`: index of the submodel whose parameter vector holds the link.
- `pooling`: the [`AbstractPooling`](@ref).
- `exponents`: the coefficient on ``\\log p_m(\\phi)`` still to be added per submodel after
  fixing has removed what it removes exactly.
- `marginals`: an [`AbstractMarginal`](@ref) per submodel where one is needed, else `nothing`.
- `ranges`: the block of the parameter vector belonging to each submodel.
- `carrier_logical`: indices of deterministic generated-quantity nodes of the carrier that
  must be recomputed after evaluation so that a logical link is current.
"""
struct MeldedModel{P<:AbstractPooling}
    submodels::Vector{BUGSModel}
    prepared::Vector{BUGSModel}
    roles::Vector{Symbol}
    links::Vector{LinkInfo}
    carrier::Int
    pooling::P
    exponents::Vector{Float64}
    marginals::Vector{Union{Nothing,AbstractMarginal}}
    ranges::Vector{UnitRange{Int}}
    carrier_logical::Vector{Int}   # deterministic generated-quantity nodes to recompute
end

function _link_is_sampled(model::BUGSModel, info::LinkInfo)
    return all(vn -> variable_type(model, vn) == ModelParameter, info.nodes)
end

function _choose_carrier(models, infos, pooling)
    M = length(models)
    logical = findall(i -> infos[i].kind == :logical, 1:M)
    if length(logical) > 1
        throw(
            ArgumentError(
                "the link is a logical node in submodels $(logical); at most one submodel " *
                "may define the link deterministically",
            ),
        )
    elseif length(logical) == 1
        return only(logical)
    end
    if pooling isa Dictatorial &&
        _link_is_sampled(models[pooling.dictator], infos[pooling.dictator])
        return pooling.dictator
    end
    c = findfirst(m -> _link_is_sampled(models[m], infos[m]), 1:M)
    c === nothing && throw(
        ArgumentError(
            "no submodel samples the link as a model parameter, so no submodel can carry it. " *
            "In every submodel the link is a generated quantity, which happens when nothing " *
            "observed depends on it; condition on some data in one submodel.",
        ),
    )
    return c
end

# Deterministic nodes the carrier must recompute after evaluation so the link is current:
# generated-quantity logical nodes that are the link or its ancestors.
function _carrier_logical_nodes(model::BUGSModel, info::LinkInfo)
    info.kind == :logical || return Int[]
    gd = model.graph_evaluation_data
    anc = _ancestors(model.g, info.nodes)
    node_set = Set(info.nodes)
    idx = Int[]
    for (i, vn) in enumerate(gd.sorted_nodes)
        (vn in node_set || vn in anc) || continue
        vt = gd.variable_types[i]
        if gd.is_stochastic_vals[i]
            vt == GeneratedQuantity && throw(
                ArgumentError(
                    "the logical link $(info.nodes) depends on $vn, an unobserved stochastic " *
                    "node that is outside the submodel's own target (a generated quantity). " *
                    "The link is then not a function of the submodel's parameters; give " *
                    "that submodel data that depends on $vn, or move $vn to another submodel.",
                ),
            )
        elseif vt == GeneratedQuantity
            push!(idx, i)
        end
    end
    return idx
end

function _complete_logical(model::BUGSModel, env::NamedTuple, idx::Vector{Int})
    gd = model.graph_evaluation_data
    for i in idx
        env = BangBang.setindex!!(
            env, gd.node_function_vals[i](env, gd.loop_vars_vals[i]), gd.sorted_nodes[i]
        )
    end
    return env
end

"""
    meld(submodels, links; pooling=ProductOfExperts(), marginals=Dict())

Join `submodels`, a vector of `BUGSModel`s sharing a link quantity, into a [`MeldedModel`](@ref)
whose log density is the Markov melded posterior

```math
\\log p_{\\text{pool}}(\\phi) + \\sum_{m=1}^{M} \\Big[\\log p_m(\\phi, \\psi_m, y_m) - \\log p_m(\\phi)\\Big].
```

# Arguments
- `submodels`: compiled models, each with its data. Private parameter names may repeat
  across submodels; the parameter vector is blocked by submodel.
- `links`: one entry per submodel naming the link in that submodel: a `VarName`, a `Symbol`,
  or a vector of them for a multivariate link. An array name expands to its element nodes in
  column-major index order, the order of `vec`. The entries must denote the same quantity,
  on the same scale, in the same order, in every submodel.
- `pooling`: an [`AbstractPooling`](@ref). Defaults to [`ProductOfExperts`](@ref), which
  needs no marginals.
- `marginals`: a `Dict{Int,Any}` from submodel index to an [`AbstractMarginal`](@ref), a
  function of the link value returning the log marginal, or a `Distribution`. Required for
  each submodel whose marginal the pooling needs and whose link is not closed. Closed links
  get an [`ExactMarginal`](@ref) automatically. A supplied marginal is always used, even
  where an exact one would have been available.

# How the submodels are evaluated
One submodel, the *carrier*, keeps the link in its parameter vector and is evaluated whole.
It is the submodel in which the link is a logical node if there is one, otherwise the
dictator under [`Dictatorial`](@ref) pooling provided it samples the link as a model
parameter, otherwise the first submodel that does. In every other submodel the link is held
at the carrier's value. `fix` is used when the pooling divides ``p_m(\\phi)`` out exactly
once (exponent ``-1``), the link is closed, and no marginal was supplied for the submodel:
it drops the link's own factor, which is the exact division. In every other case
`condition` is used, which keeps the factor, and whatever power of ``p_m(\\phi)`` the
pooling requires is added from the marginals. All held submodels are evaluated by graph
evaluation.

Returns a [`MeldedModel`](@ref). Sample it with any `LogDensityProblems` sampler, or with
`AbstractMCMC.sample(melded, sampler, n; adtype)`, which wraps it in
[`MeldedModelWithGradient`](@ref) for gradient-based samplers.
"""
function meld(
    submodels::AbstractVector{<:BUGSModel},
    links::AbstractVector;
    pooling::AbstractPooling=ProductOfExperts(),
    marginals::AbstractDict=Dict{Int,Any}(),
)
    M = length(submodels)
    M >= 1 || throw(ArgumentError("meld needs at least one submodel"))
    length(links) == M ||
        throw(ArgumentError("got $(length(links)) link specifications for $M submodels"))
    _check_pooling(pooling, M)
    for k in keys(marginals)
        k isa Integer && 1 <= k <= M ||
            throw(ArgumentError("marginals keys must be submodel indices in 1:$M, got $k"))
    end

    models = BUGSModel[m for m in submodels]
    infos = [_link_info(models[m], links[m]) for m in 1:M]
    lens = unique(i.length for i in infos)
    length(lens) == 1 || throw(
        ArgumentError(
            "the link has different sizes across submodels: " *
            join(("$(infos[m].length) in submodel $m" for m in 1:M), ", "),
        ),
    )
    trans = unique(m.transformed for m in models)
    length(trans) == 1 || throw(
        ArgumentError(
            "all submodels must agree on `transformed`; use `settrans` to align them"
        ),
    )

    carrier = _choose_carrier(models, infos, pooling)
    exponents = marginal_exponents(pooling, M)
    roles = Vector{Symbol}(undef, M)
    prepared = Vector{BUGSModel}(undef, M)
    for m in 1:M
        if m == carrier
            roles[m] = :carrier
            prepared[m] = models[m]
        elseif exponents[m] == -1 && infos[m].kind == :closed && !haskey(marginals, m)
            roles[m] = :fixed
            prepared[m] = fix(models[m], infos[m].nodes)
            exponents[m] = 0.0
        else
            roles[m] = :conditioned
            prepared[m] = condition(models[m], infos[m].nodes)
        end
    end

    margs = Vector{Union{Nothing,AbstractMarginal}}(nothing, M)
    for m in 1:M
        needed = exponents[m] != 0 || needs_all_marginals(pooling)
        if haskey(marginals, m)
            margs[m] = _as_marginal(marginals[m])
        elseif needed
            if infos[m].kind == :closed
                margs[m] = ExactMarginal(models[m], infos[m])
            else
                throw(
                    ArgumentError(
                        "$(pooling) needs the prior marginal of the link under submodel $m, " *
                        "whose link $(infos[m].nodes) is $(infos[m].kind) and so has no exact " *
                        "marginal. Pass `marginals = Dict($m => SimulatedMarginal(submodels[$m], " *
                        "link))` or a FunctionMarginal with the analytic density.",
                    ),
                )
            end
        end
    end

    dims = [LogDensityProblems.dimension(prepared[m]) for m in 1:M]
    stops = cumsum(dims)
    ranges = [(stops[m] - dims[m] + 1):stops[m] for m in 1:M]
    carrier_logical = _carrier_logical_nodes(models[carrier], infos[carrier])

    return MeldedModel{typeof(pooling)}(
        models,
        prepared,
        roles,
        infos,
        carrier,
        pooling,
        exponents,
        margs,
        ranges,
        carrier_logical,
    )
end

"""
    nsubmodels(mm::MeldedModel) -> Int

The number of submodels joined in `mm`.
"""
nsubmodels(mm::MeldedModel) = length(mm.submodels)

function Base.show(io::IO, mm::MeldedModel)
    M = nsubmodels(mm)
    println(
        io, "MeldedModel of $M submodels, dimension $(LogDensityProblems.dimension(mm))"
    )
    println(io, "  pooling: ", mm.pooling)
    for m in 1:M
        marg = if mm.marginals[m] === nothing
            ""
        else
            ", marginal: $(nameof(typeof(mm.marginals[m])))"
        end
        println(
            io,
            "  submodel $m: link $(mm.links[m].nodes) ($(mm.links[m].kind)), role $(mm.roles[m]), ",
            isempty(mm.ranges[m]) ? "no parameters" : "parameters $(mm.ranges[m])",
            mm.exponents[m] == 0 ? "" : ", marginal exponent $(mm.exponents[m])",
            marg,
        )
    end
    return nothing
end

# Evaluate every submodel at `x`, returning the per-submodel evaluation environments, the
# link value and the melded log density.
function _evaluate(mm::MeldedModel, x::AbstractVector)
    M = nsubmodels(mm)
    c = mm.carrier
    carrier_model = mm.prepared[c]
    env_c, lp = AbstractPPL.evaluate!!(carrier_model, view(x, mm.ranges[c]))
    env_c = _complete_logical(carrier_model, env_c, mm.carrier_logical)
    φ = _read_link(env_c, mm.links[c])
    envs = Vector{NamedTuple}(undef, M)
    envs[c] = env_c
    for m in 1:M
        m == c && continue
        pm = mm.prepared[m]
        env = _write_link(pm.evaluation_env, mm.links[m], φ)
        pm_at_φ = BUGSModel(pm; evaluation_env=env)
        env_m, lp_m = AbstractPPL.evaluate!!(pm_at_φ, view(x, mm.ranges[m]))
        envs[m] = env_m
        lp += lp_m
    end
    if any(!=(0), mm.exponents) || needs_all_marginals(mm.pooling)
        logmargs = map(1:M) do m
            marg = mm.marginals[m]
            marg === nothing ? zero(lp) : logmarginal(marg, φ)
        end
        lp += sum(mm.exponents[m] * logmargs[m] for m in 1:M)
        lp += logpool_extra(mm.pooling, logmargs)
    end
    return envs, φ, lp
end

function _logdensity(mm::MeldedModel, x::AbstractVector)
    return _evaluate(mm, x)[3]
end

function LogDensityProblems.logdensity(mm::MeldedModel, x::AbstractVector)
    length(x) == LogDensityProblems.dimension(mm) || throw(
        DimensionMismatch(
            "melded model has dimension $(LogDensityProblems.dimension(mm)), got $(length(x))",
        ),
    )
    try
        return _logdensity(mm, x)
    catch e
        JuliaBUGS.Model.is_impossible_point(e) && return float(eltype(x))(-Inf)
        rethrow(e)
    end
end

function LogDensityProblems.dimension(mm::MeldedModel)
    return isempty(mm.ranges) ? 0 : last(last(mm.ranges))
end

LogDensityProblems.capabilities(::Type{<:MeldedModel}) =
    LogDensityProblems.LogDensityOrder{0}()

"""
    evaluation_envs(mm::MeldedModel, x::AbstractVector) -> Vector{NamedTuple}

Evaluate the melded model at the parameter vector `x` and return one evaluation
environment per submodel, with the link written into every submodel. Use it to turn draws
of the melded parameter vector back into named values.
"""
evaluation_envs(mm::MeldedModel, x::AbstractVector) = _evaluate(mm, x)[1]

"""
    link_value(mm::MeldedModel, x::AbstractVector) -> Vector

The link value implied by the parameter vector `x`, on its constrained scale.
"""
link_value(mm::MeldedModel, x::AbstractVector) = _evaluate(mm, x)[2]

"""
    parameter_names(mm::MeldedModel) -> Vector{Tuple{Int,VarName}}

The `(submodel index, variable)` pair for every entry of the melded parameter vector, in
order. Multivariate variables are listed once per block; the lengths of the blocks are those
of the prepared submodels.
"""
function parameter_names(mm::MeldedModel)
    names = Tuple{Int,VarName}[]
    for m in 1:nsubmodels(mm)
        for vn in model_parameters(mm.prepared[m])
            push!(names, (m, vn))
        end
    end
    return names
end

"""
    getparams(mm::MeldedModel)

The current parameter vector of the melded model: the concatenation of
`getparams(prepared_submodel)` over submodels. The link comes from the carrier.
"""
function JuliaBUGS.Model.getparams(mm::MeldedModel)
    return reduce(vcat, (getparams(pm) for pm in mm.prepared); init=Float64[])
end

#######################
# Gradients
#######################

"""
    MeldedModelWithGradient(mm::MeldedModel, adtype::ADTypes.AbstractADType)

Wrap a [`MeldedModel`](@ref) with a prepared gradient so it implements
`LogDensityProblems.logdensity_and_gradient`. Load the AD backend first, together with
`DifferentiationInterface` for backends other than Mooncake, as for
`BUGSModelWithGradient`. Graph evaluation is differentiated, so the backend must handle the
graph evaluator: `AutoForwardDiff`, `AutoReverseDiff` and `AutoMooncake` do.
"""
struct MeldedModelWithGradient{AD<:ADTypes.AbstractADType,P,M<:MeldedModel}
    adtype::AD
    prep::P
    base_model::M
end

_melded_logdensity_for_gradient(x::AbstractVector, mm::MeldedModel) = _logdensity(mm, x)

function MeldedModelWithGradient(mm::MeldedModel, adtype::ADTypes.AbstractADType)
    x = getparams(mm)
    prep = if adtype isa ADTypes.AutoMooncake
        AbstractPPL.prepare(adtype, x -> _melded_logdensity_for_gradient(x, mm), x)
    else
        AbstractPPL.prepare(adtype, _melded_logdensity_for_gradient, x; context=(mm,))
    end
    return MeldedModelWithGradient(adtype, prep, mm)
end

function LogDensityProblems.logdensity(m::MeldedModelWithGradient, x::AbstractVector)
    return LogDensityProblems.logdensity(m.base_model, x)
end
LogDensityProblems.dimension(m::MeldedModelWithGradient) =
    LogDensityProblems.dimension(m.base_model)
function LogDensityProblems.capabilities(::Type{<:MeldedModelWithGradient})
    return LogDensityProblems.LogDensityOrder{1}()
end
function LogDensityProblems.logdensity_and_gradient(
    m::MeldedModelWithGradient, x::AbstractVector
)
    try
        logp, grad = AbstractPPL.value_and_gradient!!(m.prep, x)
        return (logp, copy(grad))
    catch e
        T = float(eltype(x))
        JuliaBUGS.Model.is_impossible_point(e) && return (T(-Inf), fill(T(NaN), length(x)))
        rethrow(e)
    end
end

JuliaBUGS.Model.getparams(m::MeldedModelWithGradient) = getparams(m.base_model)
evaluation_envs(m::MeldedModelWithGradient, x) = evaluation_envs(m.base_model, x)
parameter_names(m::MeldedModelWithGradient) = parameter_names(m.base_model)

#######################
# Sampling
#######################

"""
    AbstractMCMC.sample([rng,] mm::MeldedModel, sampler, N; adtype=nothing, initial_params=getparams(mm), kwargs...)

Sample the melded model with any `AbstractMCMC` sampler that accepts a
`LogDensityModel`. Gradient-based samplers need `adtype`, which wraps the model in
[`MeldedModelWithGradient`](@ref). Returns the sampler's transitions; map them back to
named values with [`evaluation_envs`](@ref).
"""
function AbstractMCMC.sample(
    rng::Random.AbstractRNG,
    mm::MeldedModel,
    sampler::AbstractMCMC.AbstractSampler,
    N_or_isdone;
    adtype::Union{Nothing,ADTypes.AbstractADType}=nothing,
    initial_params=getparams(mm),
    kwargs...,
)
    target = adtype === nothing ? mm : MeldedModelWithGradient(mm, adtype)
    return AbstractMCMC.sample(
        rng,
        AbstractMCMC.LogDensityModel(target),
        sampler,
        N_or_isdone;
        initial_params,
        kwargs...,
    )
end
function AbstractMCMC.sample(
    mm::MeldedModel, sampler::AbstractMCMC.AbstractSampler, N_or_isdone; kwargs...
)
    return AbstractMCMC.sample(Random.default_rng(), mm, sampler, N_or_isdone; kwargs...)
end

end # module Melding
