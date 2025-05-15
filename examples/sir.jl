# Example demonstrating an SIR (Susceptible-Infected-Recovered) epidemiological model 
# implemented in JuliaBUGS, using DifferentialEquations.jl to solve the ODEs.
# It showcases various MCMC sampling strategies (NUTS with AD, RWMH, parallel, distributed).

using JuliaBUGS
using JuliaBUGS: @model
using Distributions
using DifferentialEquations
using LogDensityProblems, LogDensityProblemsAD
using AbstractMCMC, AdvancedHMC, MCMCChains
using Distributed              # For distributed example

# --- SIR Ordinary Differential Equation Definition ---

# Define the SIR model dynamics
function SIR!(
    du,  # Buffer for the updated derivatives (dS/dt, dI/dt, dR/dt)
    u,   # Current state vector [S, I, R]
    p,   # Parameters [β, γ]
    t,   # Current time (not used in this simple SIR model, but required by DifferentialEquations.jl)
)
    N = 763.0 # Total population size (constant)
    S, I, R = u
    β, γ = p # Transmission rate (beta), Recovery rate (gamma)

    # Differential equations
    dS = -β * I * S / N
    dI = β * I * S / N - γ * I
    dR = γ * I

    du[1] = dS
    du[2] = dI
    du[3] = dR
end

# --- Custom Primitive Definitions for BUGS ---

# Register DifferentialEquations.jl functions to be callable from the BUGS model
JuliaBUGS.@register_primitive DifferentialEquations SIR!

# Define a function to solve the SIR ODE and return the number of infected individuals over time.
# This function will be called within the BUGS model.
JuliaBUGS.@register_primitive function solve_ode(u0, p)
    tspan = (0.0, 14.0) # Time span for the simulation (14 days)
    prob = DifferentialEquations.ODEProblem(SIR!, u0, tspan, p)
    # Solve the ODE, saving the solution at integer time steps (daily)
    sol = DifferentialEquations.solve(prob; saveat=1.0)
    # Return the predicted number of infected individuals (second component of the solution) 
    # from day 1 to day 14.
    return sol[2, 2:15]
end

# Define and register a custom Negative Binomial distribution parameterized by mean (μ) and dispersion (ϕ).
# BUGS often uses this parameterization.
JuliaBUGS.@register_primitive function NegativeBinomial2(μ, ϕ)
    # Convert (μ, ϕ) to Negative Binomial parameters (r, p)
    # Ensure μ is positive to avoid issues with p calculation
    μ_safe = max(μ, 1e-9)
    p = 1 / (1 + μ_safe / ϕ)
    r = ϕ
    return NegativeBinomial(r, p)
end

# --- BUGS Model Definition ---

@model function sir_model((; beta, gamma, phi_inv, I_data), u0)
    beta ~ truncated(Normal(2, 1), 0, nothing)
    gamma ~ truncated(Normal(0.4, 0.5), 0, nothing)
    phi_inv ~ Exponential(1 / 5)
    phi = inv(phi_inv)

    p[1] = beta
    p[2] = gamma

    predicted[1:14] = solve_ode(u0[:], p[:])

    for i in 1:14
        I_data[i] ~ NegativeBinomial2(predicted[i] + 1e-5, phi)
    end

    R0 = beta / gamma
    recovery_time = 1 / gamma
    infected[1:14] = predicted[:]
end

# --- Data and Initial Values ---

# Observed data: Number of infected individuals over 14 days
# Initial state: [S₀, I₀, R₀]
data = (
    I_data=[3, 8, 26, 76, 225, 298, 258, 233, 189, 128, 68, 29, 14, 4],
    u0=[762.0, 1.0, 0.0], # Start with S=762, I=1, R=0
)

# Initial values for MCMC chains (optional, but can help convergence)
# Using different parameter names matching the model definition for clarity
initial_θ = (beta=1.6, gamma=0.7, phi_inv=1.2) # Corresponds to [β, γ, ϕ⁻¹]
# Converting named tuple to vector for samplers that require it
initial_θ_vec = [initial_θ.beta, initial_θ.gamma, initial_θ.phi_inv]

# --- Model Instantiation ---

# Create the JuliaBUGS model instance
model = sir_model(
    (;
        beta=missing,      # Parameter to be inferred
        gamma=missing,     # Parameter to be inferred
        phi_inv=missing,   # Parameter to be inferred
        I_data=data.I_data, # Observed data
    ),
    data.u0,                # Initial conditions for the ODE
)
model = JuliaBUGS.initialize!(model, initial_θ)
model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())

# --- MCMC Sampling: NUTS with ForwardDiff AD ---

# Create an AD-aware wrapper for the model using ForwardDiff for gradients
ad_model_forwarddiff = ADgradient(:ForwardDiff, model)

# MCMC settings
n_samples = 1000
n_adapts = 500

# Run the NUTS sampler
samples_nuts_fwd = AbstractMCMC.sample(
    ad_model_forwarddiff,
    AdvancedHMC.NUTS(0.65), # No-U-Turn Sampler with step size adaptation target
    n_samples;
    chain_type=Chains,     # Store results as MCMCChains object
    n_adapts=n_adapts,     # Number of adaptation/warmup steps
    init_params=initial_θ_vec, # Starting point for the sampler
    discard_initial=n_adapts, # Discard warmup samples
)
