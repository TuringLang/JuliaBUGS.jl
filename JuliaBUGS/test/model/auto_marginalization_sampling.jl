using JuliaBUGS: @bugs, compile, settrans, getparams, initialize!
using JuliaBUGS.Model:
    set_evaluation_mode,
    UseAutoMarginalization,
    parameters,
    evaluate_with_marginalization_values!!

@testset "Auto-Marginalization Sampling (NUTS)" begin
    # 2-component GMM with fixed weights. Discrete z marginalized out.
    mixture_def = @bugs begin
        w[1] = 0.3
        w[2] = 0.7

        # Moderately informative priors to aid identifiability
        mu[1] ~ Normal(-2, 1)
        mu[2] ~ Normal(2, 1)
        sigma[1] ~ Exponential(1)
        sigma[2] ~ Exponential(1)

        for i in 1:N
            z[i] ~ Categorical(w[1:2])
            y[i] ~ Normal(mu[z[i]], sigma[z[i]])
        end
    end

    # Generate data from the ground-truth parameters
    N = 120
    true_w = [0.3, 0.7]
    true_mu = [-2.0, 2.0]
    true_sigma = [1.0, 1.0]
    rng = StableRNG(1234)
    # Partially observed assignments to break label switching and speed convergence
    z_full = Vector{Int}(undef, N)
    z_obs = Vector{Union{Int,Missing}}(undef, N)
    # First 30 guaranteed component 1, last 30 guaranteed component 2
    for i in 1:30
        z_full[i] = 1
        z_obs[i] = 1
    end
    for i in (N - 29):N
        z_full[i] = 2
        z_obs[i] = 2
    end
    # Middle indices drawn randomly
    for i in 31:(N - 30)
        z_full[i] = rand(rng, Categorical(true_w))
        z_obs[i] = missing
    end
    # Generate y
    y = Vector{Float64}(undef, N)
    for i in 1:N
        y[i] = rand(rng, Normal(true_mu[z_full[i]], true_sigma[z_full[i]]))
    end

    data = (N=N, y=y, z=z_obs)

    # Compile auto-marginalized model and wrap with AD for NUTS
    model = (
        m -> (m -> set_evaluation_mode(m, UseAutoMarginalization()))(settrans(m, true))
    )(
        compile(mixture_def, data)
    )
    # Initialize near ground truth for faster convergence
    initialize!(model, (; mu=[-2.0, 2.0], sigma=[1.0, 1.0]))
    ad_model = ADgradient(AutoForwardDiff(), model)

    # Initialize at current transformed parameters
    θ0 = getparams(model)

    # Short NUTS run to verify we recover means reasonably well
    # Use more samples to tighten estimation accuracy
    n_samples, n_adapts = 2000, 1000
    # Sample transitions (avoid requiring MCMCChains conversion here)
    chain = AbstractMCMC.sample(
        rng,
        ad_model,
        NUTS(0.65),
        n_samples;
        progress=false,
        chain_type=MCMCChains.Chains,
        n_adapts=n_adapts,
        init_params=θ0,
        discard_initial=n_adapts,
    )

    # Estimate means directly from Chains
    means = mean(chain)
    mu1_hat = means[Symbol("mu[1]")].nt.mean[1]
    mu2_hat = means[Symbol("mu[2]")].nt.mean[1]

    # With unequal weights (0.3 vs 0.7), label switching is unlikely; allow generous tolerance
    # Direct comparison to ground truth with absolute tolerance
    @test isapprox(mu1_hat, true_mu[1]; atol=0.20)
    @test isapprox(mu2_hat, true_mu[2]; atol=0.20)
end
