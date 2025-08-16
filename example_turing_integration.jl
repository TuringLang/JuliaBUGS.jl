using JuliaBUGS
using Turing
using Distributions
using Random

bugs_model_def = JuliaBUGS.@bugs begin
    # Hierarchical structure in BUGS
    mu_group ~ dnorm(0, 0.01)      # Group mean
    tau_group ~ dgamma(1, 1)       # Group precision

    for i = 1:n_subjects
        theta[i] ~ dnorm(mu_group, tau_group)  # Individual effects
    end
end

n_subjects = 5
bugs_data = (n_subjects = n_subjects,)

bugs_model = compile(bugs_model_def, bugs_data)
bugs_model =
    initialize!(bugs_model, (mu_group = 0.0, tau_group = 1.0, theta = zeros(n_subjects)))

# Step 2: Use the BUGS model as a component in a Turing model
Turing.@model function combined_model(y, n_subjects)
    # Sample the hierarchical parameters from the BUGS model
    bugs_params ~ to_distribution(bugs_model)

    # Extract the individual effects
    theta = bugs_params.theta

    # Add additional model components in Turing
    sigma ~ truncated(Normal(0, 1), 0, Inf)  # Observation noise

    # Likelihood using the parameters from BUGS model
    for i = 1:n_subjects
        y[i] ~ Normal(theta[i], sigma)
    end

    return bugs_params, sigma
end

# Generate synthetic data
true_theta = randn(n_subjects) .+ 2.0
true_sigma = 0.5
y_obs = true_theta .+ randn(n_subjects) .* true_sigma

model = combined_model(y_obs, n_subjects)

chain = sample(model, NUTS(), 1000) # crashes right now
