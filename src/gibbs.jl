using AbstractPPL
import AbstractPPL.GraphPPL: set_node_value!, get_node_value, get_model_values, set_model_values!, get_nodekind
using AbstractMCMC
using MCMCChains
using Random
using Distributions

abstract type GibbsSampler <: AbstractMCMC.AbstractSampler end

struct SampleFromPrior <: GibbsSampler 
    all_children::Dict{VarName, Vector{VarName}} # TODO: this should be a part of Model
end
SampleFromPrior(model::AbstractPPL.GraphPPL.Model) = SampleFromPrior(getchildren(model))

function getchildren(model::AbstractPPL.GraphPPL.Model)
    all_children = Dict{VarName, Vector{VarName}}()
    for vn in keys(model)
        children = []
        for vnn in keys(model)
            if Symbol(vn) in model[vnn][:input]
                push!(children, vnn)
            end
        end
        all_children[vn] = children
    end
    return all_children
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
    state = (sample, )
    return sample, state
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG, 
    model::AbstractPPL.GraphPPL.Model, 
    sampler::SampleFromPrior,
    state;
    kwargs...
)
    last_sample = state[1]
    m = deepcopy(model)  
    set_model_values!(m, last_sample)  
    
    # Metropolis within Gibbs
    for vn in keys(model)
        input, _, f, kind = m[vn]
        input_values = get_node_value(m, input)
        if kind == :Stochastic
            new_m = deepcopy(m)
            prior = f(input_values...)
            @assert prior isa Distributions.Sampleable  

            # using the prior as the proposal, so x is independent of x'
            current_value = get_node_value(m, vn)
            proposed_value = rand(rng, prior)
            set_node_value!(new_m, vn, proposed_value)
            logα = logdensityof(prior, current_value) - logdensityof(prior, proposed_value)

            freevars = getfreevaraibles!(new_m, vn, sampler.all_children, Vector{VarName}())
            push!(freevars, vn)
            for var in freevars
                input_new, _, f_new, _ = new_m[var]
                input_values_new = get_node_value(new_m, input_new)
                logα += logdensityof(f_new(input_values_new...), get_node_value(new_m, var))

                input, _, f, _ = m[var]
                input_values = get_node_value(m, input)
                logα -= logdensityof(f(input_values...), get_node_value(m, var))
            end
            
            if -randexp(rng) < logα 
                m = new_m
            end
        elseif kind == :Logical
            set_node_value!(m, vn, f(input_values...))
        else # kind == :Observations
            continue
        end
    end
    sample = get_model_values(m)
    state = (sample, logdensityof(m), )
    return sample, state
end

"""
    getfreevaraibles!(model, vn, allchildren, returnchildren)

Recursively find all the children that are stochastic or observation nodes. At the same time, propagate 
values via logical assignments.
"""
function getfreevaraibles!(model::AbstractPPL.GraphPPL.Model, vn::VarName, allchildren::Dict{VarName, Vector{VarName}}, returnchildren::Vector{VarName})
    for child in allchildren[vn]
        input, _, f, kind = model[child]
        input_values = get_node_value(model, input)
        if kind == :Logical
            set_node_value!(model, child, f(input_values...))
            getfreevaraibles!(model, child, allchildren, returnchildren)
        else
            push!(returnchildren, child)
        end
    end
    return returnchildren
end


# ---------------- Adapted from Pavan's mh branch ----------------
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

function get_namemap(m::AbstractPPL.GraphPPL.Model; stochastic_only=true)
    names = []
    nodes = []
    for vn in keys(m)
        if get_nodekind(m, vn) == :Stochastic || !stochastic_only
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
    argsort = sortperm(names)
    return names[argsort], nodes[argsort]
end

function flatten_samples(v::Vector{NamedTuple{T, S}}, dims, nodes) where {T, S}
    samples = Array{Float64}(undef, dims, length(v))
    for i in 1:length(v)
        if dims == 1
            samples[i] = reduce(vcat, v[i][Tuple(nodes)])
        else
            samples[:,i] = reduce(vcat, v[i][Tuple(nodes)])
        end
    end
    samples
end

"""
    Chains(m::Model, vals::Matrix{Float64})
Constructor for MCMCChains.Chains. 
"""
function MCMCChains.Chains(m::AbstractPPL.GraphPPL.Model, vals::Vector{NamedTuple{T, S}}) where {T, S}
    names, nodes = get_namemap(m, stochastic_only=false)
    Chains(transpose(flatten_samples(vals, length(names), nodes)), names)
end
# --------------------------------------------------------------