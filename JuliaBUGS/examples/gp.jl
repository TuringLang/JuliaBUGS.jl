# Example demonstrating the use of Gaussian Processes (GPs) within JuliaBUGS
# for modeling golf putting accuracy based on distance.
# This example uses AbstractGPs.jl for the GP implementation and AdvancedHMC.jl
# for sampling from the posterior distribution.

using JuliaBUGS
using JuliaBUGS: @model

# Required packages for GP modeling and MCMC
using AbstractGPs, Distributions, LogExpFunctions, ForwardDiff
using LogDensityProblems
using ADTypes
using AbstractMCMC, AdvancedHMC, MCMCChains

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

# Define a function callable within the BUGS model to compute GP predictions.
# BUGS requires functions to operate on basic numerical types, so this wraps the GP call.
function gp_predict(v, l, d, jitter)
    # Create a GP with a Squared Exponential kernel using the provided hyperparameters
    kernel = v * with_lengthscale(SEKernel(), l)
    gp = GP(kernel)
    # Return the distribution representing the GP evaluated at distances `d` with jitter
    return gp(d, jitter)
end

# Define a function for the observation model (likelihood).
# This creates a product distribution of Binomials, one for each distance.
function y_distribution(n, f_latent)
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

# Use graph evaluation mode with ForwardDiff AD (required for user-defined primitives)
model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
grad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoForwardDiff())

# --- MCMC Sampling ---

# Sample from the posterior distribution using AdvancedHMC's NUTS sampler
samples_and_stats = AbstractMCMC.sample(
    grad_model,
    AdvancedHMC.NUTS(0.65), # No-U-Turn Sampler
    1000;                   # Total number of samples
    chain_type=Chains,      # Store results as MCMCChains object
    n_adapts=500,           # Number of adaptation steps for NUTS
    discard_initial=500,    # Number of initial samples (warmup) to discard
)
