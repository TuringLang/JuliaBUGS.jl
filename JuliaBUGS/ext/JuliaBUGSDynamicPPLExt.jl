module JuliaBUGSDynamicPPLExt

using Bijectors
using Distributions
using DynamicPPL
using JuliaBUGS
using JuliaBUGS.Model:
    BUGSMarginalDistribution,
    _constrain,
    _constrain_with_logjac,
    _unconstrain,
    _unconstrain_with_logjac
using LogDensityProblems

# The constrain map `u -> x` a `FixedTransform` carries, and its inverse. Two of them
# compare equal when they belong to the same model object, which is what DynamicPPL
# checks when a value comes back carrying a transform.
struct BUGSConstrain{D<:BUGSMarginalDistribution}
    distribution::D
end
(t::BUGSConstrain)(u::AbstractVector{<:Real}) = _constrain(t.distribution, u)
Base.:(==)(a::BUGSConstrain, b::BUGSConstrain) =
    a.distribution.model === b.distribution.model
Base.isequal(a::BUGSConstrain, b::BUGSConstrain) = a == b
Base.hash(t::BUGSConstrain, h::UInt) = hash(objectid(t.distribution.model), h)

struct BUGSUnconstrain{D<:BUGSMarginalDistribution}
    distribution::D
end
(t::BUGSUnconstrain)(x::AbstractVector{<:Real}) = _unconstrain(t.distribution, x)

_transform(d::BUGSMarginalDistribution) = BUGSConstrain(d)

# Whatever transform an initial value arrives with, store it in unconstrained space
# under the model's own constrain map, so the tilde path never applies a second one.
function _fixed_value(d::BUGSMarginalDistribution, transformed_value)
    transform = DynamicPPL.get_transform(transformed_value)
    value = DynamicPPL.get_internal_value(transformed_value)
    u = if transform isa DynamicPPL.FixedTransform
        transform.transform == _transform(d) ||
            error("BUGS model parameters have a different fixed transform")
        return transformed_value
    elseif transform isa DynamicPPL.DynamicLink
        value
    elseif transform isa DynamicPPL.Unlink
        _unconstrain_or_keep(d, Bijectors.VectorBijectors.from_vec(d)(value))
    elseif transform isa DynamicPPL.NoTransform
        _unconstrain_or_keep(d, value)
    else
        error("unsupported transform $(typeof(transform)) for a BUGS marginal distribution")
    end
    u === nothing && return transformed_value
    return DynamicPPL.TransformedValue(u, DynamicPPL.FixedTransform(_transform(d)))
end

function _unconstrain_or_keep(d::BUGSMarginalDistribution, x)
    result = _unconstrain_with_logjac(d, x)
    return result === nothing ? nothing : first(result)
end

function _assume!!(d::BUGSMarginalDistribution, vn, template, vi, transformed_value)
    transform = DynamicPPL.get_transform(transformed_value)
    value = DynamicPPL.get_internal_value(transformed_value)
    parameters, logjac = if transform isa DynamicPPL.FixedTransform
        transform.transform == _transform(d) ||
            error("BUGS model parameters have a different fixed transform")
        # The accumulator wants the Jacobian of the link, `x -> u`, which is the
        # negative of the constrain map's.
        parameters, constrain_logjac = _constrain_with_logjac(d, value)
        parameters, -constrain_logjac
    elseif transform isa DynamicPPL.Unlink
        parameters = Bijectors.VectorBijectors.from_vec(d)(value)
        parameters, zero(eltype(parameters))
    elseif transform isa DynamicPPL.NoTransform
        value, zero(eltype(value))
    else
        error("unsupported transform $(typeof(transform)) for a BUGS marginal distribution")
    end
    vi = DynamicPPL.accumulate_assume!!(
        vi, parameters, transformed_value, logjac, vn, d, template
    )
    return parameters, vi
end

function DynamicPPL.tilde_assume!!(
    context::DynamicPPL.InitContext,
    d::BUGSMarginalDistribution,
    vn::DynamicPPL.VarName,
    template,
    vi::DynamicPPL.AbstractVarInfo,
)
    transformed_value = DynamicPPL.init(context.rng, vn, d, context.strategy)
    transformed_value = _fixed_value(d, transformed_value)
    vi = DynamicPPL.setindex_with_dist!!(vi, transformed_value, d, vn, template)
    return _assume!!(d, vn, template, vi, transformed_value)
end

function DynamicPPL.tilde_assume!!(
    ::DynamicPPL.DefaultContext,
    d::BUGSMarginalDistribution,
    vn::DynamicPPL.VarName,
    template,
    vi::DynamicPPL.AbstractVarInfo,
)
    transformed_value = DynamicPPL.get_transformed_value(vi, vn)
    return _assume!!(d, vn, template, vi, transformed_value)
end

const VectorBijectors = Bijectors.VectorBijectors
VectorBijectors.from_linked_vec(d::BUGSMarginalDistribution) = BUGSConstrain(d)
VectorBijectors.to_linked_vec(d::BUGSMarginalDistribution) = BUGSUnconstrain(d)
function VectorBijectors.linked_vec_length(d::BUGSMarginalDistribution)
    return LogDensityProblems.dimension(d.model)
end
function VectorBijectors.linked_optic_vec(d::BUGSMarginalDistribution)
    return fill(nothing, VectorBijectors.linked_vec_length(d))
end

end
