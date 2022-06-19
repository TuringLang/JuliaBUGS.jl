using AbstractMCMC
using AdvancedMH
using AbstractPPL
using MCMCChains

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

# step!
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
    logjoint_proposed = logdensityof(proposed_model, proposed)
    # decide whether to accept or reject the next proposal
    if logjoint_sample < logjoint_proposed + randexp(rng)
        sample = proposed
        logjoint_sample = logjoint_proposed
        set_model_values!(model, sample)
    end

    return sample, (sample, logjoint_sample)
end

function propose(rng::Random.AbstractRNG, 
                 spl::AdvancedMH.MHSampler,
                 m::Model{Tnames}) where {Tnames}
    deepcopy(m)
    
    s_nodes = get_stochastic_nodes(m)
    vals = get_node_value(m, s_nodes)

    proposal_values = vals .+ rand(rng, spl.proposal)
    
    for node in s_nodes
        set_node_value!(m, VarName{node}(), proposal_values)
    end
end

# function update!(
#     rng::Random.AbstractRNG,
#     m::AbstractPPL.GraphPPL.Model,
#     values::NamedTuple{Snames, Svalues}
#     )
#     for k in keys(values)
#         set_node_value!(m, VarName{k}(), values[n])
#     end

#     for vn in keys(m)
#         input, _, f, kind = m[vn]
#         input_values = get_node_value(m, input)
#         if kind == :Stochastic || kind == :Observations
#             set_node_value!(m, vn, rand(rng, f(input_values...)))
#         else
#             set_node_value!(m, vn, f(input_values...))
#         end
#     end
#     m
# end


function get_stochastic_nodes(m::AbstractPPL.GraphPPL.Model)
    nodes = Vector{Symbol}()
    for vn in keys(m)
        if get_nodekind(m, vn) == :Stochastic
            push!(nodes, getsym(vn))
        end
    end
    Tuple(nodes)
end

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