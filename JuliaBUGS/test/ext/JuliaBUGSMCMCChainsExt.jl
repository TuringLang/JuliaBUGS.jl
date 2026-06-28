# test the Chain construction with a simple Bayesian linear regression model
@testset "MCMCChains extension" begin
    model_def = @bugs begin
        # Likelihood
        for i in 1:N
            y[i] ~ dnorm(mu[i], tau)
            mu[i] = alpha + beta * x[i]
        end

        # Priors
        alpha ~ dnorm(0, 0.01)
        beta ~ dnorm(0, 0.01)
        sigma ~ dunif(0, 10)

        # Precision
        tau = pow(sigma, -2)

        # Generated Quantities for testing purposes
        gen_quant = alpha + beta * sigma
    end

    # ground truth: alpha = 3, beta = 2, sigma = 1
    data = (
        N=10,
        x=[0.0, 1.11, 2.22, 3.33, 4.44, 5.56, 6.67, 7.78, 8.89, 10.0],
        y=[1.58, 4.80, 7.10, 8.86, 11.73, 14.52, 18.22, 18.73, 21.04, 22.93],
    )

    model = compile(model_def, data, (;))
    ad_model = compile(model_def, data, (;); adtype=AutoReverseDiff(; compile=true))
    n_samples, n_adapts = 2000, 1000

    D = LogDensityProblems.dimension(ad_model)
    initial_θ = rand(D)

    hmc_chain = Base.invokelatest(
        AbstractMCMC.sample,
        ad_model,
        NUTS(0.8),
        n_samples;
        progress=false,
        chain_type=Chains,
        n_adapts=n_adapts,
        init_params=initial_θ,
        discard_initial=n_adapts,
    )
    @test hmc_chain.name_map[:parameters] == [
        :sigma
        :beta
        :alpha
        :gen_quant
    ]
    @test hmc_chain.name_map[:internals] == [
        :lp,
        :n_steps,
        :is_accept,
        :acceptance_rate,
        :log_density,
        :hamiltonian_energy,
        :hamiltonian_energy_error,
        :max_hamiltonian_energy_error,
        :tree_depth,
        :numerical_error,
        :step_size,
        :nom_step_size,
        :is_adapt,
    ]
    means = mean(hmc_chain)
    @test means[:alpha].nt.mean[1] ≈ 2.3 atol = 0.3
    @test means[:beta].nt.mean[1] ≈ 2.1 atol = 0.3
    @test means[:sigma].nt.mean[1] ≈ 0.9 atol = 0.3
    @test means[:gen_quant].nt.mean[1] ≈ 4.2 atol = 0.3

    n_samples, n_adapts = 20000, 5000

    mh_chain = AbstractMCMC.sample(
        model,
        RWMH(MvNormal(zeros(D), I)),
        n_samples;
        progress=false,
        chain_type=Chains,
        n_adapts=n_adapts,
        init_params=initial_θ,
        discard_initial=n_adapts,
    )

    @test mh_chain.name_map[:parameters] == [
        :sigma
        :beta
        :alpha
        :gen_quant
    ]
    @test mh_chain.name_map[:internals] == [:lp]
    means = mean(mh_chain)
    @test means[:alpha].nt.mean[1] ≈ 2.3 atol = 0.3
    @test means[:beta].nt.mean[1] ≈ 2.1 atol = 0.3
    @test means[:sigma].nt.mean[1] ≈ 0.9 atol = 0.3
    @test means[:gen_quant].nt.mean[1] ≈ 4.2 atol = 0.3

    # test for more complicated varnames
    model_def = @bugs begin
        A[1, 1:3] ~ Dirichlet(ones(3))
        A[2, 1:3] ~ Dirichlet(ones(3))
        A[3, 1:3] ~ Dirichlet(ones(3))

        mu[1:3] ~ MvNormal(zeros(3), 10 * Diagonal(ones(3)))
        sigma[1] ~ InverseGamma(2, 3)
        sigma[2] ~ InverseGamma(2, 3)
        sigma[3] ~ InverseGamma(2, 3)
    end
    ad_model = compile(model_def, (;); adtype=AutoReverseDiff(; compile=true))
    hmc_chain = AbstractMCMC.sample(
        ad_model, NUTS(0.8), 10; progress=false, chain_type=Chains
    )
    @test Set(hmc_chain.name_map[:parameters]) == Set([
        Symbol("sigma[3]"),
        Symbol("sigma[2]"),
        Symbol("sigma[1]"),
        Symbol("mu[1:3][1]"),
        Symbol("mu[1:3][2]"),
        Symbol("mu[1:3][3]"),
        Symbol("A[3, 1:3][1]"),
        Symbol("A[3, 1:3][2]"),
        Symbol("A[3, 1:3][3]"),
        Symbol("A[2, 1:3][1]"),
        Symbol("A[2, 1:3][2]"),
        Symbol("A[2, 1:3][3]"),
        Symbol("A[1, 1:3][1]"),
        Symbol("A[1, 1:3][2]"),
        Symbol("A[1, 1:3][3]"),
    ])
end

@testset "forward-sampled generated quantities in chains" begin
    model_def = @bugs begin
        mu ~ dnorm(0, 1)
        y ~ dnorm(mu, 1)
        z ~ dnorm(mu, 1)      # stochastic generated quantity
        pred = mu + 1.0       # deterministic generated quantity
    end
    model = compile(model_def, (; y=0.5))
    @test LogDensityProblems.dimension(model) == 1

    # Synthetic posterior draws of the single model parameter `mu`.
    samples = [[m] for m in range(-1.0, 1.0; length=25)]
    chn = JuliaBUGS.gen_chains(model, samples, Symbol[], []; rng=StableRNG(2024))

    colnames = names(chn)
    @test :mu in colnames
    @test :z in colnames       # stochastic generated quantity surfaced
    @test :pred in colnames    # deterministic generated quantity surfaced

    A = Array(chn)
    mucol = A[:, findfirst(==(:mu), colnames)]
    zcol = A[:, findfirst(==(:z), colnames)]
    predcol = A[:, findfirst(==(:pred), colnames)]

    # Stochastic generated quantity is forward-sampled, not frozen at one value.
    @test length(unique(zcol)) > 1
    # Deterministic generated quantity equals f(model parameter) for every draw.
    @test all(predcol .≈ mucol .+ 1.0)
    # Model-parameter column matches the synthetic samples in order.
    @test mucol ≈ [s[1] for s in samples]
end

@testset "chains use cached generated-quantity classification" begin
    model_def = @bugs begin
        x ~ dnorm(0, 1)
        pred = x + 1.0
    end
    model = compile(model_def, (;))

    @test isempty(JuliaBUGS.Model.generated_quantities(model))

    samples = [[-0.5], [0.5]]
    chn = JuliaBUGS.gen_chains(model, samples, Symbol[], []; rng=StableRNG(2024))

    colnames = names(chn)
    @test :x in colnames
    @test :pred ∉ colnames
end

@testset "auto-marginalized chains reconstruct generated quantities from samples" begin
    model_def = @bugs begin
        mu ~ Normal(0, 1)
        z ~ Categorical(w[1:2])
        y ~ Normal(mu + z, 1)
        pred = mu + 1.0
    end

    model = compile(model_def, (; w=[0.5, 0.5], y=1.0))
    model = JuliaBUGS.settrans(model, true)
    model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseAutoMarginalization())
    @test LogDensityProblems.dimension(model) == 1

    samples = [[m] for m in range(-1.0, 1.0; length=25)]
    chn = JuliaBUGS.gen_chains(model, samples, Symbol[], []; rng=StableRNG(2024))

    colnames = names(chn)
    @test :mu in colnames
    @test :z in colnames       # recovered marginalized latent
    @test :pred in colnames    # deterministic generated quantity

    A = Array(chn)
    mucol = A[:, findfirst(==(:mu), colnames)]
    zcol = A[:, findfirst(==(:z), colnames)]
    predcol = A[:, findfirst(==(:pred), colnames)]

    @test mucol ≈ [s[1] for s in samples]
    @test predcol ≈ mucol .+ 1.0
    @test all(z -> z in (1, 2), zcol)
end
