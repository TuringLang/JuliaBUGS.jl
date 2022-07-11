using AbstractMCMC
using AdvancedMH
using AbstractPPL
using MCMCChains
using ComponentArrays

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::AbstractPPL.GraphPPL.Model, 
    sampler::AdvancedMH.MHSampler;
    init_from=rand(rng, model),  # `rand` draws a named tuple from the prior
    kwargs...
)
    state = (init_from, logdensityof(model, init_from),)
    return AbstractMCMC.step(rng, model, sampler, state; kwargs...)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::AbstractPPL.GraphPPL.Model, 
    sampler::AdvancedMH.MHSampler, 
    state;
    kwargs...
)
    # state is just a tuple containing the last sample and its log probability
    sample, logjoint_sample = state
    proposed_model = propose(rng, spl, m)
    logjoint_proposed = logdensityof(proposed_model)
    # decide whether to accept or reject the next proposal
    if logjoint_sample < logjoint_proposed + randexp(rng)
        sample = get_model_values(proposed_model)
        logjoint_sample = logjoint_proposed
        set_model_values!(model, sample)
        return sample, (sample, logjoint_sample)
    else
        AbstractMCMC.step(rng, model, sampler, state; kwargs...)
    end
end

function propose(rng::Random.AbstractRNG, 
                 spl::AdvancedMH.MHSampler,
                 m::Model{Tnames}) where {Tnames}
    _m = deepcopy(m)
    
    s_nodes = get_nodes(_m, :Stochastic)
    vals = get_node_value(_m, s_nodes)
    proposal_values = vals .+ rand(rng, spl.proposal)

    for (i, node) in enumerate(s_nodes)
        set_node_value!(_m, VarName{node}(), proposal_values[i])
    end
    _m
end

# ----------------------------------------------------------------------
# MCMCChains interface
# ----------------------------------------------------------------------
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