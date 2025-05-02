# Example demonstrating the use of Gaussian Processes (GPs) within JuliaBUGS
# for modeling golf putting accuracy based on distance.
# This example uses AbstractGPs.jl for the GP implementation and AdvancedHMC.jl
# for sampling from the posterior distribution.

using JuliaBUGS
using JuliaBUGS: @model

# Required packages for GP modeling and MCMC
using AbstractGPs, Distributions, LogExpFunctions
using LogDensityProblems, LogDensityProblemsAD
using AbstractMCMC, AdvancedHMC, MCMCChains

# Differentiation backend
using DifferentiationInterface
using Mooncake: Mooncake

# --- Data Definition ---

# Golf putting data from Gelman et al. (BDA3, Chapter 5)
golf_data = (
    distance=[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], # Distance in feet
    n=[ # Number of putts attempted
        1443,
        694,
        455,
        353,
        272,
        256,
        240,
        217,
        200,
        237,
        202,
        192,
        174,
        167,
        201,
        195,
        191,
        147,
        152,
    ],
    y=[ # Number of successful putts
        1346,
        577,
        337,
        208,
        149,
        136,
        111,
        69,
        67,
        75,
        52,
        46,
        54,
        28,
        27,
        31,
        33,
        20,
        24,
    ],
)

# Prepare data in the format expected by the BUGS model
data = (
    d=golf_data.distance,
    n=golf_data.n,
    y=golf_data.y,
    jitter=1e-6, # Small value added to GP kernel diagonal for numerical stability
    N=length(golf_data.distance),
)

# --- BUGS Model Definition ---

@model function gp_golf_putting((; v, l, f_latent, y), N, n, d, jitter)
    # Priors for GP hyperparameters
    v ~ Distributions.Gamma(2, 1) # Variance
    l ~ Distributions.Gamma(4, 1) # Lengthscale

    # Latent GP function values
    # f_latent represents the underlying putting success probability (on logit scale)
    # modeled by a GP.
    f_latent[1:N] ~ gp_predict(v, l, d[1:N], jitter)

    # Likelihood: Binomial distribution for observed successes
    # The success probability for each distance is the logistic transformation of the latent GP value.
    y[1:N] ~ y_distribution(n[1:N], f_latent[1:N])
end

# --- Custom Primitive Definitions for BUGS ---

# Register the GP kernel type with JuliaBUGS
# This allows using AbstractGPs types directly in the model definition.
JuliaBUGS.@register_primitive GP with_lengthscale SEKernel

# Define a function callable within the BUGS model to compute GP predictions.
# BUGS requires functions to operate on basic numerical types, so this wraps the GP call.
JuliaBUGS.@register_primitive function gp_predict(v, l, d, jitter)
    # Create a GP with a Squared Exponential kernel using the provided hyperparameters
    kernel = v * with_lengthscale(SEKernel(), l)
    gp = GP(kernel)
    # Return the distribution representing the GP evaluated at distances `d` with jitter
    return gp(d, jitter)
end

# Define a function for the observation model (likelihood).
# This creates a product distribution of Binomials, one for each distance.
JuliaBUGS.@register_primitive function y_distribution(n, f_latent)
    return product_distribution(Binomial.(n, logistic.(f_latent)))
end

# --- Model Instantiation ---

# Create the JuliaBUGS model instance
# Provide initial values (missing for parameters to be inferred) and observed data
model = gp_golf_putting(
    (; v=missing, l=missing, f_latent=fill(missing, data.N), y=data.y),
    data.N,      # Number of observations
    data.n,      # Observed attempts
    data.d,      # Observed distances
    data.jitter, # Numerical stability term
)

# Optionally, set the evaluation mode. Using generated functions can be faster.
# model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())

# --- MCMC Setup with Custom LogDensityProblems Wrapper ---

# We need a wrapper around the JuliaBUGS model to interface with LogDensityProblems
# and utilize automatic differentiation (AD) via Mooncake.jl for gradient computation,
# which is required by AdvancedHMC.

struct BUGSMooncakeModel{T,P}
    model::T # The JuliaBUGS model
    prep::P  # Pre-allocated workspace for gradient computation using Mooncake
end

# Define the function to compute the log density using the JuliaBUGS model's internal function
f(x) = model.log_density_computation_function(model.evaluation_env, x)

# Prepare the differentiation backend (Mooncake)
backend = AutoMooncake(; config=nothing)
x_init = rand(LogDensityProblems.dimension(model)) # Initial point for testing/preparation
prep = prepare_gradient(f, backend, x_init)

# Create the wrapped model instance
bugsmooncake = BUGSMooncakeModel(model, prep)

# --- LogDensityProblems Interface Implementation for the Wrapper ---

# Define logdensity function for the wrapper
function LogDensityProblems.logdensity(model::BUGSMooncakeModel, x::AbstractVector)
    return f(x) # Calls the underlying JuliaBUGS log density function
end

# Define logdensity_and_gradient function using the prepared DifferentiationInterface setup
function LogDensityProblems.logdensity_and_gradient(
    model::BUGSMooncakeModel, x::AbstractVector
)
    # Computes both the log density and its gradient using Mooncake AD
    return DifferentiationInterface.value_and_gradient(
        f, model.prep, AutoMooncake(; config=nothing), x
    )
end

# Define dimension function
function LogDensityProblems.dimension(model::BUGSMooncakeModel)
    return LogDensityProblems.dimension(model.model) # Delegates to the original model
end

# Define a custom bundle_samples function to convert the AdvancedHMC.Transition to a Chains object
function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedHMC.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSMooncakeModel},
    sampler::AdvancedHMC.AbstractHMCSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    stats_names = collect(keys(merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))))
    stats_values = [
        vcat([ts[i].z.ℓπ.value..., collect(values(AdvancedHMC.stat(ts[i])))...]) for
        i in eachindex(ts)
    ]

    return JuliaBUGS.gen_chains(
        logdensitymodel.logdensity.model,
        [t.z.θ for t in ts],
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

# Specify capabilities (indicates gradient availability)
function LogDensityProblems.capabilities(::Type{<:BUGSMooncakeModel})
    return LogDensityProblems.LogDensityOrder{1}() # Can compute up to the gradient
end

# --- MCMC Sampling ---

# Sample from the posterior distribution using AdvancedHMC's NUTS sampler
samples_and_stats = AbstractMCMC.sample(
    AbstractMCMC.LogDensityModel(bugsmooncake), # Wrap the model for AbstractMCMC
    AdvancedHMC.NUTS(0.65), # No-U-Turn Sampler
    1000;                   # Total number of samples
    chain_type=Chains,      # Store results as MCMCChains object
    n_adapts=500,           # Number of adaptation steps for NUTS
    discard_initial=500,    # Number of initial samples (warmup) to discard;
)
