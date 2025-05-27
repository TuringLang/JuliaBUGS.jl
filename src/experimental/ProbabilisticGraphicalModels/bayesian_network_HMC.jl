using JuliaBUGS
using LogDensityProblems
using BangBang
using Graphs
using MetaGraphsNext
using Distributions
using JuliaBUGS
using JuliaBUGS: BUGSGraph, VarName, NodeInfo
using AbstractPPL
using Bijectors: Bijectors
using LinearAlgebra: Cholesky
using LogExpFunctions
using AdvancedHMC
using Random
using LogDensityProblemsAD
using ReverseDiff
using AbstractMCMC
include("bayesian_network.jl")
# Now include your custom implementations
include("logdensityproblems.jl")
include("conditioning.jl")
include("functions.jl")

# Optional: Verify method definitions
@show methods(LogDensityProblems.logdensity)
@show methods(LogDensityProblems.dimension)


# 1. Define the BUGS model
test_model = @bugs begin
    a ~ dnorm(0, 1)
    b ~ dnorm(0, 1)
    c ~ dnorm(0, 1)
end

# 2. Compile the model with initial values
inits = (a=1.0, b=2.0, c=3.0)
model = compile(test_model, NamedTuple(), inits)
print(model.transformed_param_length)
# 3. Translate BUGSGraph to BayesianNetwork
g = model.g
bn = translate_BUGSGraph_to_BayesianNetwork(g, model.evaluation_env, model)
print(bn.transformed_param_length)
@show LogDensityProblems.dimension(bn) 
# 4. Make the log-density problem AD-compatible
ad_model = ADgradient(:ReverseDiff, bn; compile=Val(true))

# 5. Set up HMC/NUTS sampler
D = LogDensityProblems.dimension(bn)
initial_θ = randn(D)  # Or use transformed initial values if you have them

# Metric and integrator configuration
metric = DiagEuclideanMetric(D)
integrator = Leapfrog(0.1)  # Initial step size will be adapted

# 2. Build NUTS sampler with adaptation
D = LogDensityProblems.dimension(bn)
initial_θ = randn(D)
n_samples, n_adapts = 2000, 1000

sampler = NUTS(0.8)  # This is all you need for a standard NUTS sampler

samples = AbstractMCMC.sample(
    Random.default_rng(),
    ad_model,
    sampler,
    n_samples + n_adapts;
    n_adapts = n_adapts,
    initial_params = initial_θ,
    progress = true
)


using JuliaBUGS, LogDensityProblemsAD, AdvancedHMC, MCMCChains, Random

# 1. Define model with explicit array declaration
test_model = @bugs begin
    μ[1] ~ dnorm(0, 1)
    μ[2] ~ dnorm(0, 1)
    π ~ dbeta(1, 1)
    
    # Fixed array definition
    for k in 1:2
        p[k] = ifelse(k == 1, π, 1 - π)
    end
    
    for i in 1:N
        z[i] ~ dcat(p)
        y[i] ~ dnorm(μ[z[i]], 1)
    end
end
# 2. Generate synthetic data
Random.seed!(42)
y_obs = [1.2, -1.5, 0.8]  # Example observations from mixture components
N = length(y_obs)  # Define N from data
# 3. Compile model with data
model = compile(test_model, (y=y_obs,N = N))

# 4. Translate to BayesianNetwork
bn = translate_BUGSGraph_to_BayesianNetwork(model.g, model.evaluation_env, model)

# 5. Verify parameter space (should be 3: μ1, μ2, π)
@show LogDensityProblems.dimension(bn)  # Should be 3

# 6. Create AD-compatible model
ad_model = ADgradient(:ForwardDiff, bn; compile=Val(true))

# 7. Configure sampler with careful initialization
initial_θ = [0.0, 0.0, 0.5]  # Reasonable starting values
n_samples, n_adapts = 1000, 500

# 8. Run sampling with adaptation
chain = AbstractMCMC.sample(
    ad_model,
    NUTS(0.65),  # Conservative target acceptance rate
    n_samples;
    n_adapts = n_adapts,
    initial_params = initial_θ,
    chain_type = Chains,
    discard_initial = n_adapts
)

# 9. Analyze results
println("\nPosterior summary:")
display(summary(chain))
using JuliaBUGS, LogDensityProblemsAD, AdvancedHMC, MCMCChains, Random

# 1. Define model with discrete uniform latent variable (automatically marginalized)
test_model = @bugs begin
    # Discrete uniform selection between two means
    p[1] = 0.5  # Fixed probability for component 1
    p[2] = 0.5  # Fixed probability for component 2
    
    μ[1] ~ dnorm(0, 1)  # Mean 1
    μ[2] ~ dnorm(0, 1)  # Mean 2
    
    z ~ dcat(p[:])       # Discrete uniform selection (z ∈ {1,2})
    y ~ dnorm(μ[z], 1)  # Observation depends on selected component
end

# 2. Provide observed data
data = (y = 1.5,)


# 3. Compile and inspect the model
model = compile(test_model, data)
include("bayesian_network.jl")
# Now include your custom implementations
include("logdensityproblems.jl")
include("conditioning.jl")
include("functions.jl")


# 4. Translate to BayesianNetwork and check parameter dimension
bn = translate_BUGSGraph_to_BayesianNetwork(model.g, model.evaluation_env, model)
# Fix the node type for z (make it discrete)
for (i, name) in enumerate(bn.names)
    if string(name) == "z"
        bn.node_types[i] = :discrete
        break
    end
end

@show LogDensityProblems.dimension(bn)
@show LogDensityProblems.logdensity(bn, [0.0, 0.0])



using LogDensityProblems
using LogDensityProblemsAD
using ForwardDiff
# point of ad_model is that LogDensityProblemsAD.ADgradient is just a wrapper,
# where LogDensityProblems.logdensity_and_gradient is automatically defined for the wrapper type
LogDensityProblems.logdensity_and_gradient(ad_model, [0.0, 0.0])

# 5. Sampling configuration
ad_model = ADgradient(:ReverseDiff, bn)
initial_θ = [0.0, 0.0]  # Reasonable starting values

# 6. Run NUTS sampling
chain = AbstractMCMC.sample(
    ad_model,
    NUTS(0.65),
    1000;
    n_adapts = 500,
    initial_params = initial_θ,
    discard_initial = 500
)


using AdvancedHMC, AbstractMCMC, LogDensityProblems, MCMCChains

# Sampling parameters
n_samples, n_adapts = 2000, 1000

ad_model = LogDensityProblemsAD.ADgradient(:ReverseDiff, bn)  # or :ForwardDiff

# Check dimension
println("Parameter dimension: ", LogDensityProblems.dimension(ad_model))

# Initial parameters
initial_θ = [0.0, 0.0]  # or randn(2)

# Run NUTS sampling - NOTE: no chain_type specified, use initial_params
chain = AbstractMCMC.sample(
    ad_model,
    NUTS(0.65),           # or NUTS(0.8)
    1000;                 # number of samples
    n_adapts = 500,       # adaptation steps
    initial_params = initial_θ,  # NOTE: initial_params, not init_params
    discard_initial = 500  # discard adaptation samples
)

# Display results
display(chain)

using StatsPlots
# Check what we got
println("Type of chain: ", typeof(chain))
println("Length: ", length(chain))

# Extract the parameter samples from the transitions
samples = [transition.z.θ for transition in chain]  # θ contains the parameter vector
samples_matrix = hcat(samples...)'  # Convert to matrix (n_samples × n_params)

# Create parameter names
param_names = ["μ[1]", "μ[2]"]

# Create proper MCMCChains object
mcmc_chain = MCMCChains.Chains(samples_matrix, param_names)

# Now you can plot and analyze
display(mcmc_chain)
plot(mcmc_chain)

# Check diagnostics
using MCMCDiagnosticTools
println("Effective sample sizes: ", ess(chain))
println("R-hat values: ", rhat(chain))