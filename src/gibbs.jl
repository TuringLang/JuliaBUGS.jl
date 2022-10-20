using AbstractMCMC
using AbstractPPL
using MCMCChains
using Random
using Distributions
using Graphs

struct Trace <: AbstractPPL.AbstractModelTrace
    value::Vector{Real}
    logp::Vector{Real}
end

abstract type GibbsSampler <: AbstractMCMC.AbstractSampler end

abstract type MHWithinGibbs <: GibbsSampler end

struct ProposeFromPrior <: MHWithinGibbs end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::BUGSGraph, 
    sampler::GibbsSampler;
    kwargs...
)
    num_nodes = numnodes(model)
    value = Vector{Real}(undef, num_nodes)
    logp = Vector{Real}(undef, num_nodes)
    for node in model.sortednode
        if model.isobserve[node]
            value[node] = model.observed_values[node]
            logp[node] = logpdf(getdistribution(model, node, value), model.observed_values[node])
        else
            if node in keys(model.initializations)
                value[node] = model.initializations[node]
            else
                value[node] = rand(rng, getdistribution(model, node, value))
            end
            logp[node] = logpdf(getdistribution(model, node, value), value[node])
        end
    end
    return value[assumednodes(model)], Trace(value, logp)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::BUGSGraph, 
    sampler::ProposeFromPrior,
    trace::Trace;
    kwargs...
)
    for node in model.sortednode
        if model.isobserve[node]
            trace.logp[node] = logpdf(getdistribution(model, node, trace), trace.value[node])
        else
            d = getdistribution(model, node, trace)
            x = trace.value[node]
            x′ = rand(rng, d)
            d′ = getdistribution(model, node, trace, Dict(node => x′))
            @assert d == d′
            logα = logpdf(d′, x) - logpdf(d, x′)

            logα += logpdf(d′, x′) - logpdf(d, x)
            for v in children(model, node)
                logα += logpdf(getdistribution(model, v, trace, Dict(node => x′)), trace.value[v])
                logα -= logpdf(getdistribution(model, v, trace), trace.value[v])
            end

            if -randexp(rng) < logα 
                trace.value[node] = x′
                trace.logp[node] = logpdf(d′, x′)
            else
                trace.logp[node] = logpdf(d, x)
            end
        end
    end
    return deepcopy(trace.value)[assumednodes(model)], trace
end

function AbstractMCMC.bundle_samples(
    samples, 
    model::BUGSGraph, 
    ::AbstractMCMC.AbstractSampler, 
    ::Any, 
    ::Type; 
    kwargs...
)
    return sort(Chains(samples, model.reverse_nodeenum[assumednodes(model)]))
end