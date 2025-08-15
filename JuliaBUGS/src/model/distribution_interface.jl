"""
    BUGSModelDistribution{M<:BUGSModel} <: Distributions.Distribution{NamedTupleVariate{K},S}

A distribution wrapper for BUGSModel that implements the Distributions.jl interface.
This allows a BUGSModel to be used as a distribution that samples NamedTuples of its parameters.

The distribution uses LogDensityProblems interface for evaluation and supports:
- Sampling parameter NamedTuples
- Computing log densities
- Working with transformed/untransformed parameter spaces
"""
struct BUGSModelDistribution{K,M<:BUGSModel,S<:ValueSupport} <: 
       Distribution{NamedTupleVariate{K},S}
    model::M
end

function BUGSModelDistribution(model::BUGSModel)
    # Get unique parameter names as symbols (to handle arrays)
    param_syms = unique(Symbol(AbstractPPL.getsym(vn)) for vn in parameters(model))
    param_names = Tuple(param_syms)
    
    # Determine value support based on model parameters
    # BUGSModel can have both continuous and discrete parameters
    # For now, we'll default to Continuous if any continuous parameters exist
    S = Continuous  # Could be made more sophisticated based on actual parameter types
    
    return BUGSModelDistribution{param_names,typeof(model),S}(model)
end

"""
    to_distribution(model::BUGSModel)

Convert a BUGSModel to a Distribution that samples NamedTuples of its parameters.

# Examples
```julia
model = compile(model_def, data)
dist = to_distribution(model)
sample = rand(dist)  # Returns a NamedTuple of parameter values
logpdf(dist, sample)  # Computes log density
```
"""
to_distribution(model::BUGSModel) = BUGSModelDistribution(model)

# Implement Distribution interface

Base.eltype(::Type{<:BUGSModelDistribution}) = NamedTuple

function Distributions.rand(rng::AbstractRNG, d::BUGSModelDistribution{K}) where {K}
    # Use ancestral sampling to generate a sample
    evaluation_env, _ = evaluate!!(rng, d.model; sample_all=false)
    
    # Group parameters by their base symbol
    param_groups = Dict{Symbol,Vector{Pair{VarName,Any}}}()
    for vn in parameters(d.model)
        sym = Symbol(AbstractPPL.getsym(vn))
        val = AbstractPPL.get(evaluation_env, vn)
        
        if !haskey(param_groups, sym)
            param_groups[sym] = Pair{VarName,Any}[]
        end
        push!(param_groups[sym], vn => val)
    end
    
    # Construct the result dictionary
    param_dict = Dict{Symbol,Any}()
    for (sym, pairs) in param_groups
        if length(pairs) == 1
            # Single value parameter
            param_dict[sym] = pairs[1].second
        else
            # Array parameter - need to reconstruct the array
            # For simplicity, assume it's a 1D array indexed 1:n
            # A more sophisticated approach would analyze the actual indices
            vals = [p.second for p in pairs]
            param_dict[sym] = vals
        end
    end
    
    # Create NamedTuple with correct order
    return NamedTuple{K}(Tuple(param_dict[k] for k in K))
end

function Distributions.logpdf(d::BUGSModelDistribution{K}, x::NamedTuple) where {K}
    # Convert NamedTuple to flattened vector for the model
    # First, update the model's evaluation environment with the NamedTuple values
    new_env = d.model.evaluation_env
    
    for (key, val) in pairs(x)
        # Find all VarNames that match this key
        matching_vns = [vn for vn in parameters(d.model) if Symbol(AbstractPPL.getsym(vn)) == key]
        
        if length(matching_vns) == 1
            # Single parameter (or single array parameter)
            new_env = BangBang.setindex!!(new_env, val, matching_vns[1])
        elseif length(matching_vns) > 1
            # Multiple indexed parameters (e.g., theta[1], theta[2], ...)
            # Assume val is an array and distribute values
            if val isa AbstractArray
                for (i, vn) in enumerate(matching_vns)
                    new_env = BangBang.setindex!!(new_env, val[i], vn)
                end
            else
                # Single value for multiple parameters? This shouldn't happen normally
                for vn in matching_vns
                    new_env = BangBang.setindex!!(new_env, val, vn)
                end
            end
        end
    end
    
    # Create a new model with updated environment
    updated_model = BUGSModel(d.model; evaluation_env=new_env)
    
    # Compute log density using the LogDensityProblems interface
    if d.model.transformed
        # If model is in transformed space, we need to transform the parameters
        # For now, we'll use the untransformed space for simplicity
        _, logp = evaluate!!(updated_model; transformed=false)
    else
        _, logp = evaluate!!(updated_model)
    end
    
    return logp
end

function Distributions.pdf(d::BUGSModelDistribution, x::NamedTuple)
    exp(logpdf(d, x))
end

# Support functions

function Distributions.insupport(d::BUGSModelDistribution{K}, x::NamedTuple) where {K}
    # Check if the NamedTuple has the right fields
    if !all(haskey(x, k) for k in K)
        return false
    end
    
    # For now, return true if we can evaluate the log density
    # A more sophisticated check would validate parameter constraints
    try
        logp = logpdf(d, x)
        return isfinite(logp)
    catch
        return false
    end
end

# Sampling multiple values
function Base.rand(rng::AbstractRNG, d::BUGSModelDistribution{K}, n::Int) where {K}
    [rand(rng, d) for _ in 1:n]
end

function Base.rand(rng::AbstractRNG, d::BUGSModelDistribution{K}, dims::Dims) where {K}
    [rand(rng, d) for _ in CartesianIndices(dims)]
end

# Optional: implement mean, mode, etc. if meaningful for the model
# These would require MCMC or optimization techniques