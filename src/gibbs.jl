using AbstractMCMC
using MCMCChains
using Random
using Distributions
using Graphs

abstract type GibbsSampler <: AbstractMCMC.AbstractSampler end

abstract type MHWithinGibbs <: GibbsSampler end

struct SampleFromPrior <: MHWithinGibbs end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::BUGSGraph, 
    sampler::GibbsSampler;
    kwargs...
)
    num_nodes = getnumnodes(model)
    value = Vector{Real}(undef, num_nodes)
    logp = Vector{Real}(undef, num_nodes)
    for node in model.sortednode
        if model.isoberve[node]
            value[node] = model.observed_values[node]
            logp[node] = logdensityof(getdistribution(model, node, value), value[node])
        else
            if node in keys(model.initializations)
                value[node] = model.initializations[node]
            else
                value[node] = rand(rng, getdistribution(model, node, value))
            end
            logp[node] = logdensityof(getdistribution(model, node, value), value[node])
        end
    end
    return value, Trace(value, logp)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::BUGSGraph, 
    sampler::SampleFromPrior,
    state::Trace;
    kwargs...
)
    num_nodes = getnumnodes(model)
    value = deepcopy(state.value)
    logp = deepcopy(state.logp)
    for node in model.sortednode
        if model.isoberve[node]
            value[node] = state.value[node]
            logp[node] = state.logp[node]
        else
            current_value = state.value[node]
            prior = getdistribution(model, node, value)
            proposed_value = rand(rng, prior)
            logα = logdensityof(prior, current_value) - logdensityof(prior, proposed_value)
            for child in outneighbors(model.digraph, node)
                logα += logdensityof(getdistribution(model, child, value), state.value[child]) - state.logp[child]
            end
            if -randexp(rng) < logα 
                value[node] = proposed_value
                logp[node] = logdensityof(prior, proposed_value)
            else
                value[node] = current_value
                logp[node] = state.logp[node]
            end
        end
    end
    return value, Trace(value, logp)
end

function AbstractMCMC.bundle_samples(
    samples, 
    m::BUGSGraph, 
    ::AbstractMCMC.AbstractSampler, 
    ::Any, 
    ::Type; 
    kwargs...
)
    return Chains(samples, m.reverse_nodeenum[m.sortednode])
end