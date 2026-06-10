# test FlexiChain construction with a simple Bayesian linear regression model
@testset "FlexiChains extension" begin
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
        chain_type=VNChain,
        n_adapts=n_adapts,
        init_params=initial_θ,
        discard_initial=n_adapts,
    )
    @test hmc_chain isa VNChain
    @test size(hmc_chain) == (n_samples, 1)
    @test Set(FlexiChains.parameters(hmc_chain)) == Set([
        @varname(sigma), @varname(beta), @varname(alpha), @varname(gen_quant)
    ])
    @test Set(FlexiChains.get_name.(FlexiChains.extras(hmc_chain))) == Set([
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
    ])
    hmc_means = mean(hmc_chain)
    @test hmc_means[@varname(alpha)] ≈ 2.3 atol = 0.3
    @test hmc_means[@varname(beta)] ≈ 2.1 atol = 0.3
    @test hmc_means[@varname(sigma)] ≈ 0.9 atol = 0.3
    @test hmc_means[@varname(gen_quant)] ≈ 4.2 atol = 0.3

    # conversion to MCMCChains.Chains (provided by FlexiChains' MCMCChains extension)
    mcmc_chain = MCMCChains.Chains(hmc_chain)
    @test mcmc_chain isa MCMCChains.Chains
    @test Set([:alpha, :beta, :sigma, :gen_quant]) ⊆ Set(names(mcmc_chain, :parameters))
    @test mean(mcmc_chain[:alpha]) ≈ hmc_means[@varname(alpha)] atol = 1e-10

    n_samples, n_adapts = 20000, 5000

    mh_chain = AbstractMCMC.sample(
        model,
        RWMH(MvNormal(zeros(D), I)),
        n_samples;
        progress=false,
        chain_type=VNChain,
        n_adapts=n_adapts,
        init_params=initial_θ,
        discard_initial=n_adapts,
    )
    @test mh_chain isa VNChain
    @test Set(FlexiChains.parameters(mh_chain)) == Set([
        @varname(sigma), @varname(beta), @varname(alpha), @varname(gen_quant)
    ])
    @test FlexiChains.get_name.(FlexiChains.extras(mh_chain)) == [:lp]
    mh_means = mean(mh_chain)
    @test mh_means[@varname(alpha)] ≈ 2.3 atol = 0.3
    @test mh_means[@varname(beta)] ≈ 2.1 atol = 0.3
    @test mh_means[@varname(sigma)] ≈ 0.9 atol = 0.3
    @test mh_means[@varname(gen_quant)] ≈ 4.2 atol = 0.3

    # array-valued parameters are stored whole, keyed by their VarName
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
        ad_model, NUTS(0.8), 10; progress=false, chain_type=VNChain
    )
    @test Set(FlexiChains.parameters(hmc_chain)) == Set([
        @varname(A[1, 1:3]),
        @varname(A[2, 1:3]),
        @varname(A[3, 1:3]),
        @varname(mu[1:3]),
        @varname(sigma[1]),
        @varname(sigma[2]),
        @varname(sigma[3]),
    ])
    mu_draws = hmc_chain[@varname(mu[1:3]), stack=false]
    @test length(mu_draws) == 10
    @test all(v -> v isa AbstractVector && length(v) == 3, mu_draws)

    @testset "Gibbs with chain_type=VNChain" begin
        model_def = @bugs begin
            μ ~ Normal(0, 10)
            τ ~ Gamma(1, 1)
            for i in 1:N
                θ[i] ~ Normal(μ, 1 / sqrt(τ))
                y[i] ~ Normal(θ[i], 1)
            end
        end
        gibbs_model = compile(model_def, (; N=5, y=[1.0, 1.5, 2.0, 2.5, 3.0]))

        sampler_map = OrderedDict(
            @varname(μ) => IndependentMH(),
            @varname(τ) => IndependentMH(),
            @varname(θ) => IndependentMH(),
        )
        gibbs = Gibbs(gibbs_model, sampler_map)

        rng = Random.MersenneTwister(123)
        chain = Base.invokelatest(
            sample, rng, gibbs_model, gibbs, 100; progress=false, chain_type=VNChain
        )

        @test chain isa VNChain
        @test size(chain) == (100, 1)
        @test length(FlexiChains.parameters(chain)) == 7  # μ, τ, θ[1:5]
    end

    @testset "IndependentMH with chain_type=VNChain" begin
        model_def = @bugs begin
            mu ~ Normal(0, 1)
            y ~ Normal(mu, 0.1)
        end
        imh_model = compile(model_def, (; y=1.0))

        rng = Random.MersenneTwister(999)
        chain = sample(
            rng, imh_model, IndependentMH(), 100; chain_type=VNChain, progress=false
        )

        @test chain isa VNChain
        @test @varname(mu) in FlexiChains.parameters(chain)
    end
end
