module JuliaBUGSFlexiChainsExt

using AbstractMCMC
using FlexiChains: FlexiChains, Extra, Parameter
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient, OrderedDict
using JuliaBUGS.AbstractPPL: VarName
using Random: default_rng

function AbstractMCMC.bundle_samples(
    transitions::AbstractVector,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:Union{BUGSModel,BUGSModelWithGradient}},
    sampler::AbstractMCMC.AbstractSampler,
    last_sampler_state,
    chain_type::Type{FlexiChains.VNChain};
    save_state=false,
    stats=missing,
    discard_initial::Int=0,
    thinning::Int=1,
    _kwargs...,
)
    # AbstractMCMC's bundle hook does not receive the positional sampling RNG; this matches
    # JuliaBUGS' existing generated-quantity reconstruction behavior.
    params_with_stats = JuliaBUGS.Model._transitions_to_params_with_stats(
        default_rng(), logdensitymodel, sampler, transitions
    )

    niters = length(params_with_stats)
    dicts = map(params_with_stats) do sample
        isempty(sample.extras) || throw(
            ArgumentError(
                "cannot store nonempty ParamsWithStats.extras in a FlexiChain, " *
                "because FlexiChains has only one non-parameter Extra category",
            ),
        )
        dict = OrderedDict{FlexiChains.ParameterOrExtra{<:VarName},Any}(
            Parameter(vn) => value for (vn, value) in pairs(sample.params)
        )
        for (name, value) in pairs(sample.stats)
            dict[Extra(name)] = value
        end
        dict
    end

    sampling_time = stats === missing ? missing : stats.stop - stats.start
    sampler_state = save_state ? last_sampler_state : missing
    first_iteration = discard_initial + 1
    iter_indices = if thinning == 1
        first_iteration:(first_iteration + niters - 1)
    else
        range(first_iteration; step=thinning, length=niters)
    end

    return FlexiChains.FlexiChain{VarName}(
        niters,
        1,
        dicts;
        iter_indices,
        chain_indices=1:1,
        sampling_time=[sampling_time],
        last_sampler_state=[sampler_state],
    )
end

end
