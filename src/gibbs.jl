using AbstractPPL
import AbstractPPL.GraphPPL: set_node_value!, get_node_value, get_model_values, set_model_values!, get_nodekind
using AbstractMCMC
using MCMCChains
using AdvancedMH
using Random
using BugsModels

struct GibbsSampler <: AbstractMCMC.AbstractSampler end

# TODO: strictly speaking, this is not Markov blanket, as it only contains children and itself
function getmarkovblacket(model::AbstractPPL.GraphPPL.Model, x::Symbol)
    V = Vector{Symbol}()    
    for v in keys(model)
        if v == VarName{x}() || x in model[v][:input]
            push!(V, getsym(v))
        end
    end
    return V
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::AbstractPPL.GraphPPL.Model, 
    sampler::GibbsSampler;
    kwargs...
)
    m = deepcopy(model)    
    for vn in keys(m)
        input, _, f, kind = m[vn]
        input_values = get_node_value(m, input)
        if kind == :Stochastic
            sample = rand(rng, f(input_values...))
            set_node_value!(m, vn, sample)
        elseif kind == :Logical
            set_node_value!(m, vn, f(input_values...))
        else # kind == :Observations
            continue
        end
    end
    sample = get_model_values(m)
    state = (sample, logdensityof(m, sample), )
    return sample, state
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::AbstractPPL.GraphPPL.Model, 
    sampler::GibbsSampler,
    state;
    kwargs...
)
    last_sample, logjoint_sample = state
    m = deepcopy(model)  
    set_model_values!(m, last_sample)  
    
    # Metropolis within Gibbs: Murphy, Probabilistic Machine Learning, Advanced Topics, 12.3.6
    for vn in keys(m)
        input, _, f, kind = m[vn]
        input_values = get_node_value(m, input)
        if kind == :Stochastic
            new_m = deepcopy(m)
            prior = f(input_values...)
            # using the prior as the proposal, so x is independent of x'
            original_value = get_node_value(m, vn)
            proposal = rand(rng, prior)
            set_node_value!(new_m, vn, proposal)
            # the distributions should be the same for trace and proposed trace, given
            # we only modify single value and it's a DAG
            logα = logdensityof(prior, original_value) - logdensityof(prior, proposal)
            # for now, just compute the log joint, later can use markov blanket to 
            # simplify computation
            logjoint_proposed = logdensityof(new_m)
            logα += logjoint_proposed - logjoint_sample
            if -randexp(rng) < logα 
                m = new_m
                logjoint_sample = logjoint_proposed
            end
        elseif kind == :Logical
            set_node_value!(m, vn, f(input_values...))
        else # kind == :Observations
            continue
        end
    end
    sample = get_model_values(m)
    state = (sample, logdensityof(m, sample), )
    return sample, state
end

# ---------------- taken from Pavan's mh branch ----------------
function AbstractMCMC.bundle_samples(
    samples, 
    m::AbstractPPL.GraphPPL.Model, 
    ::AbstractMCMC.AbstractSampler, 
    ::Any, 
    ::Type; 
    kwargs...
)
    return Chains(m, samples)
end

function get_namemap(m::AbstractPPL.GraphPPL.Model)
    names = []
    nodes = []
    for vn in keys(m)
        if get_nodekind(m, vn) == :Stochastic
            v = get_node_value(m, vn)
            key = getsym(vn)
            push!(nodes, key)
            if length(v) == 1
                push!(names, Symbol("$(key)"))
            else    
                for i in 1:length(v)
                    push!(names, Symbol("$(key)_$i"))
                end
            end
        end
    end
    names, nodes
end

function flatten_samples(v::Vector{NamedTuple{T, S}}, dims, nodes) where {T, S}
    samples = Array{Float64}(undef, dims, length(v))
    for i in 1:length(v)
        samples[:,i] = reduce(vcat, v[i][Tuple(nodes)])
    end
    samples
end

"""
    Chains(m::Model, vals::Matrix{Float64})
Constructor for MCMCChains.Chains. 
"""
function MCMCChains.Chains(m::AbstractPPL.GraphPPL.Model, vals::Vector{NamedTuple{T, S}}) where {T, S}
    names, nodes = get_namemap(m)
    Chains(transpose(flatten_samples(vals, length(names), nodes)), names)
end
# --------------------------------------------------------------