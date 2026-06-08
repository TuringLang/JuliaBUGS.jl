module JuliaBUGSDynamicPPLExt

# Lets a `BUGSModelDistribution` (from `to_distribution`) be used as the right-hand side of a
# `~` inside a DynamicPPL `@model`, e.g.
#
#     d = to_distribution(compiled_bugs_model)
#     DynamicPPL.@model function outer()
#         theta ~ d                    # draws the BUGS model's parameters as a NamedTuple
#         y ~ Normal(f(theta.x), 1)    # use a BUGS latent downstream
#     end
#
# DynamicPPL (>= 0.42) stores every random variable's realised value as a flat real vector,
# vectorising it through the `Bijectors.VectorBijectors` interface; so a NamedTuple-variate
# distribution must provide `to_vec`/`from_vec`/`vec_length` to be storable and scoreable in
# a `VarInfo` (and hence usable with `logjoint`/`logprior`/`loglikelihood`, MH, SMC, etc.).
#
# We provide them by delegating to a *shape-only* `product_distribution` over the variate's
# fields. Its component distributions exist purely to supply an identity flatten/unflatten of
# the right shape; the density always comes from `Distributions.logpdf(::BUGSModelDistribution,
# …)`. Because `to_distribution` is a constrained-space density with no log-abs-det-Jacobian,
# only the *unlinked* methods are defined. The *linked* methods (`to_linked_vec`/
# `from_linked_vec`) are intentionally left undefined, so a gradient-based sampler — which
# would need an unconstrained transform + Jacobian the wrapper does not provide — fails loudly
# instead of silently sampling the wrong (unadjusted) density. For gradient-based inference,
# sample the underlying `BUGSModel` through its `LogDensityProblems` interface instead.

using JuliaBUGS.Model: BUGSModelDistribution
using Bijectors: Bijectors
using Distributions: Distributions, Normal, product_distribution

const VB = Bijectors.VectorBijectors

# A placeholder distribution whose VectorBijectors vectorisation is the identity, with the
# same shape as `v`. Only its shape matters; its density is never used.
_shape_dist(::Real) = Normal()
_shape_dist(v::AbstractArray) = product_distribution(fill(Normal(), size(v)...))

# A product distribution whose (unlinked) vectorisation matches the NamedTuple variate of `d`,
# built from the shapes of the variate's fields in the current evaluation environment.
function _shape_product(d::BUGSModelDistribution{names}) where {names}
    env = d.model.evaluation_env
    return product_distribution(
        NamedTuple{names}(map(s -> _shape_dist(getfield(env, s)), names))
    )
end

VB.to_vec(d::BUGSModelDistribution) = VB.to_vec(_shape_product(d))
VB.from_vec(d::BUGSModelDistribution) = VB.from_vec(_shape_product(d))
VB.vec_length(d::BUGSModelDistribution) = VB.vec_length(_shape_product(d))
VB.optic_vec(d::BUGSModelDistribution) = VB.optic_vec(_shape_product(d))

end
