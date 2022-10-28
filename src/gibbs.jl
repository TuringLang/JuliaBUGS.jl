using AbstractMCMC
using AbstractPPL
using MCMCChains
using Random
using Distributions
using Graphs, MetaGraphsNext

struct Trace <: AbstractPPL.AbstractModelTrace
    value::Dict{Symbol, Real}
    logp::Dict{Symbol, Real}
end

struct GraphModel <: AbstractPPL.AbstractProbabilisticProgram
    g :: MetaDiGraph
    sorted_nodes::Vector{Symbol}
end

function GraphModel(g::MetaDiGraph)
    sorted_nodes = (x->label_for(g, x)).(topological_sort_by_dfs(g))
    return GraphModel(g, sorted_nodes)
end

abstract type GibbsSampler <: AbstractMCMC.AbstractSampler end

abstract type MHWithinGibbs <: GibbsSampler end

struct ProposeFromPrior <: MHWithinGibbs end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::GraphModel, 
    sampler::GibbsSampler;
    kwargs...
)
    value = Dict{Symbol, Real}()
    logp = Dict{Symbol, Float64}()
    for node in model.sorted_nodes
        if model.g[node].is_data
            data = model.g[node].data
            value[node] = data
            logp[node] = logpdf(getdistribution(model.g, node, value), data)
        else
            if haskey(kwargs, :initializations) && node in keys(kwargs[:initializations])
                value[node] = kwargs[:initializations][node]
            else
                value[node] = rand(rng, getdistribution(model.g, node, value))
            end
            logp[node] = logpdf(getdistribution(model.g, node, value), value[node])
        end
    end
    report_variables = [n for n in model.sorted_nodes if !model.g[n].is_data]
    return [value[v] for v in report_variables], (Trace(value, logp), report_variables,)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::GraphModel, 
    sampler::ProposeFromPrior,
    state;
    kwargs...
)
    trace, report_variables = state
    for node in model.sorted_nodes
        if model.g[node].is_data
            trace.logp[node] = logpdf(getdistribution(model.g, node, trace.value), trace.value[node])
        else
            d = getdistribution(model.g, node, trace.value)
            x = trace.value[node]
            x′ = rand(rng, d)
            d′ = getdistribution(model.g, node, trace.value, Dict(node => x′))
            @assert d == d′
            logα = logpdf(d′, x) - logpdf(d, x′)

            logα += logpdf(d′, x′) - logpdf(d, x)
            for c in outneighbors(model.g, code_for(model.g, node))
                v = label_for(model.g, c)
                logα += logpdf(getdistribution(model.g, v, trace.value, Dict(node => x′)), trace.value[v])
                logα -= logpdf(getdistribution(model.g, v, trace.value), trace.value[v])
            end

            if -randexp(rng) < logα 
                trace.value[node] = x′
                trace.logp[node] = logpdf(d′, x′)
            else
                trace.logp[node] = logpdf(d, x)
            end
        end
    end
    return [trace.value[v] for v in report_variables], (trace, report_variables,)
end

function AbstractMCMC.bundle_samples(
    samples, 
    model::GraphModel, 
    ::AbstractMCMC.AbstractSampler, 
    ::Any, 
    ::Type; 
    kwargs...
)
    report_varaibles = [n for n in model.sorted_nodes if !model.g[n].is_data]
    return sort(Chains(samples, report_varaibles))
end