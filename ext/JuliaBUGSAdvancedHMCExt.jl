module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using ADTypes
using JuliaBUGS
using JuliaBUGS: BUGSModel, getparams, initialize!
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.Random
using MCMCChains: Chains

import JuliaBUGS: gibbs_internal

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler_tuple::Tuple{<:AdvancedHMC.AbstractHMCSampler,<:ADTypes.AbstractADType},
    state=nothing,
)
    # Extract sampler and AD backend from tuple
    sampler, ad_backend = sampler_tuple
    return _gibbs_internal_hmc(rng, cond_model, sampler, ad_backend, state)
end

# Error for plain HMC/NUTS samplers without explicit AD backend
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::AdvancedHMC.AbstractHMCSampler,
    state=nothing,
)
    return error(
        "Gradient-based samplers (HMC/NUTS) require an explicit AD backend. " *
        "Use a tuple like ($(typeof(sampler).name.name)(...), AutoForwardDiff()) or " *
        "($(typeof(sampler).name.name)(...), AutoReverseDiff()) instead.",
    )
end

function _gibbs_internal_hmc(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler, ad_backend, state
)
    # Wrap model with AD gradient computation
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(ad_backend, cond_model)
    )

    # Take HMC/NUTS step
    if isnothing(state)
        # Initial step requires initial parameters
        t, s = AbstractMCMC.step(
            rng,
            logdensitymodel,
            sampler;
            n_adapts=0,  # Disable adaptation within Gibbs
            initial_params=getparams(cond_model),
        )
    else
        # Use existing state for subsequent steps
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    end

    # Update model with new parameters and return evaluation environment
    updated_model = initialize!(cond_model, t.z.θ)
    return updated_model.evaluation_env, s
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedHMC.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    sampler::AdvancedHMC.AbstractHMCSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
<<<<<<< main
    using DynamicPPL: get_transform_info, invlink

=======
    # Extract parameter values and statistics from transitions
    param_samples = [t.z.θ for t in ts]

    # Collect statistic names and values
    # Include log probability and HMC-specific stats (step size, acceptance, etc.)
>>>>>>> sunxd/v0.10
    stats_names = collect(keys(merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))))
    stats_values = [
        vcat(ts[i].z.ℓπ.value, collect(values(AdvancedHMC.stat(ts[i])))) for
        i in eachindex(ts)
    ]

<<<<<<< main
    trans = get_transform_info(logdensitymodel.logdensity)
    param_vals = [invlink(trans, t.z) for t in ts]

    return JuliaBUGS.gen_chains(
        logdensitymodel,
        param_vals,
=======
    # Delegate to gen_chains for proper parameter naming from BUGSModel
    return JuliaBUGS.gen_chains(
        logdensitymodel,
        param_samples,
>>>>>>> sunxd/v0.10
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

<<<<<<< main
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::HMC
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(:ReverseDiff, cond_model)
    )
    t, s = AbstractMCMC.step(
        rng,
        logdensitymodel,
        sampler;
        n_adapts=0,
        initial_params=JuliaBUGS.getparams(cond_model),
    )
    updated_model = initialize!(cond_model, t.z.θ)
    return JuliaBUGS.getparams(
        BangBang.setproperty!!(
            updated_model.base_model, :evaluation_env, updated_model.evaluation_env
        ),
    )
end

function AbstractMCMC.step(
    rng::AbstractRNG,
    model::AbstractBUGSModel,
    sampler::HMC;
    n_adapts=0,
    initial_params=nothing,
    kwargs...
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(:ReverseDiff, model)
    )
    t, s = AbstractMCMC.step(
        rng,
        logdensitymodel,
        sampler;
        n_adapts=n_adapts,
        initial_params=initial_params,
        kwargs...
    )

    vi = JuliaBUGS.varinfo_from_θ(model, t.z.θ)
    ctx = LogDensityContext()
    _, vi_gen = evaluate!!(model, ctx, vi)

    all_values = Dict{Symbol, Any}()
    for (name, val) in JuliaBUGS.getparams(vi_gen)
        if should_save(name, model)
            all_values[name] = val
        end
    end

    return all_values, s
end

function should_save(name::Symbol, model::AbstractBUGSModel)
    if hasproperty(model, :saved_variables) && model.saved_variables !== nothing
        return name in model.saved_variables
    end
    return true
end

=======
>>>>>>> sunxd/v0.10
end

