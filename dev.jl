using JuliaBUGS
using LogDensityProblemsAD, ReverseDiff
using AdvancedHMC, AbstractMCMC, LogDensityProblems, MCMCChains

data = (
    r=[10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n=[39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2=[0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N=21,
)

model_def = @bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(
            alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
        )
    end
    alpha0 ~ dnorm(0.0, 1.0E-6)
    alpha1 ~ dnorm(0.0, 1.0E-6)
    alpha2 ~ dnorm(0.0, 1.0E-6)
    alpha12 ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end

model = compile(model_def, data)
ad_model = ADgradient(:ReverseDiff, model; compile=Val(false))

n_samples, n_adapts = 2000, 1000

D = LogDensityProblems.dimension(model);

# Better initialization
initial_θ = zeros(D)
# Set tau to a reasonable positive value
initial_θ[1] = 1.0  # tau
# Set alpha parameters to small values near 0
initial_θ[2:5] .= 0.0  # alpha12, alpha2, alpha1, alpha0
# Set random effects b[i] to small values near 0
initial_θ[6:end] .= 0.0

n_chain = 2

# Test with a single evaluation first
println("Initial log density: ", LogDensityProblems.logdensity(ad_model, initial_θ))

samples_and_stats = AbstractMCMC.sample(
    ad_model,
    NUTS(0.8),
    AbstractMCMC.MCMCThreads(),
    n_samples,
    n_chain,
    ;
    chain_type=Chains,
    n_adapts=n_adapts,
    init_params=fill(initial_θ, n_chain),  # Same initial values for all chains
    discard_initial=n_adapts,
)