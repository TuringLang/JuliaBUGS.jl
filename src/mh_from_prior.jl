"""
    MHFromPrior <: AbstractMCMC.AbstractSampler

A Metropolis-Hastings sampler that proposes new values by sampling from the prior distribution.

This sampler is particularly useful within Gibbs sampling for discrete parameters or when
the conditional distribution is difficult to sample from directly.

# Key Features
- Proposes new values by sampling from the prior
- Only samples unobserved variables (fixes issue #250)
- Can be used standalone or within Gibbs sampling
- Implements full AbstractMCMC interface

# Examples
```julia
using JuliaBUGS, Random, AbstractMCMC

# Define a simple model
model_def = @bugs begin
    p ~ Beta(2, 2)
    for i in 1:N
        y[i] ~ Bernoulli(p)
    end
end

# Compile with data
model = compile(model_def, (; N=10, y=[1,0,1,1,0,1,0,1,1,0]))

# Sample using MHFromPrior
chain = sample(Random.default_rng(), model, MHFromPrior(), 1000)
```
"""
struct MHFromPrior <: AbstractMCMC.AbstractSampler end

"""
    MHFromPriorState{E<:NamedTuple,L<:Real}

State for the MHFromPrior sampler.

# Fields
- `evaluation_env::E`: Current evaluation environment containing all variable values
- `logp::L`: Current log posterior density
"""
struct MHFromPriorState{E<:NamedTuple,L<:Real}
    evaluation_env::E
    logp::L
end

# Initial step
function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::MHFromPrior;
    initial_params=nothing,
    kwargs...
)
    model = logdensitymodel.logdensity
    
    # Initialize with provided params or sample from prior
    if isnothing(initial_params)
        # Sample from prior for unobserved variables only
        evaluation_env, logp = evaluate!!(rng, model; sample_all=false)
    else
        # Use provided initial parameters
        model = initialize!(model, initial_params)
        evaluation_env, logp = evaluate!!(model)
    end
    
    # Return evaluation environment directly (efficient with smart copying)
    return evaluation_env, MHFromPriorState(evaluation_env, logp)
end

# Subsequent steps
function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::MHFromPrior,
    state::MHFromPriorState;
    kwargs...
)
    model = logdensitymodel.logdensity
    
    # Use smart copy for efficiency
    current_env = Model.smart_copy_evaluation_env(state.evaluation_env, model.mutable_symbols)
    model = BangBang.setproperty!!(model, :evaluation_env, current_env)
    
    # Current log density
    logp_current = state.logp
    
    # Propose new values by sampling from prior (only unobserved variables)
    proposed_env, logp_proposed = evaluate!!(rng, model; sample_all=false)
    
    # Metropolis-Hastings acceptance ratio
    # log(α) = log(p(proposed|data)) - log(p(current|data))
    #        = log_posterior(proposed) - log_posterior(current)
    if logp_proposed - logp_current > log(rand(rng))
        # Accept proposal
        return proposed_env, MHFromPriorState(proposed_env, logp_proposed)
    else
        # Reject proposal, keep current state
        return state.evaluation_env, state
    end
end

# Bundle samples for chain construction
function AbstractMCMC.bundle_samples(
    samples::Vector,  # Contains evaluation environments
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::MHFromPrior,
    states::Vector,
    ::Type{T};
    kwargs...
) where {T}
    model = logdensitymodel.logdensity
    
    # Extract parameter values from evaluation environments
    param_samples = Vector{Vector{Float64}}()
    for env in samples
        # Temporarily set the environment to extract parameters
        model_with_env = BangBang.setproperty!!(model, :evaluation_env, env)
        push!(param_samples, JuliaBUGS.getparams(model_with_env))
    end
    
    # Extract log densities from states
    logps = [state.logp for state in states]
    
    return JuliaBUGS.gen_chains(
        logdensitymodel,
        param_samples,
        [:lp],
        [[lp] for lp in logps];
        kwargs...
    )
end

# For use within Gibbs sampling
"""
    gibbs_internal(rng, cond_model, ::MHFromPrior)

Internal function for using MHFromPrior within Gibbs sampling.
Returns parameter values in the format expected by Gibbs.
"""
function gibbs_internal(rng::Random.AbstractRNG, cond_model::BUGSModel, ::MHFromPrior)
    # Get current values and log density
    current_env = cond_model.evaluation_env
    current_env_copy = Model.smart_copy_evaluation_env(current_env, cond_model.mutable_symbols)
    model_with_current = BangBang.setproperty!!(cond_model, :evaluation_env, current_env_copy)
    _, logp_current = evaluate!!(model_with_current)
    
    # Propose new values (only sampling unobserved variables)
    proposed_env, logp_proposed = evaluate!!(rng, cond_model; sample_all=false)
    
    # Metropolis-Hastings acceptance
    if logp_proposed - logp_current > log(rand(rng))
        # Accept proposal
        return JuliaBUGS.getparams(
            BangBang.setproperty!!(cond_model.base_model, :evaluation_env, proposed_env)
        )
    else
        # Reject proposal
        return JuliaBUGS.getparams(
            BangBang.setproperty!!(cond_model.base_model, :evaluation_env, current_env)
        )
    end
end
