using JuliaBUGS: Gibbs, IndependentMH, BUGSModelWithGradient, getparams, settrans
using JuliaBUGS.Model: UseAutoMarginalization, set_evaluation_mode

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
    @test Set(FlexiChains.parameters(hmc_chain)) ==
        Set([@varname(sigma), @varname(beta), @varname(alpha), @varname(gen_quant)])
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

    # sampler statistics are stored as Extra entries with usable values
    lp = hmc_chain[FlexiChains.Extra(:lp)]
    @test eltype(lp) <: AbstractFloat
    @test all(isfinite, lp)
    @test length(unique(vec(lp))) > 1
    @test all(x -> x isa Bool, vec(hmc_chain[FlexiChains.Extra(:numerical_error)]))

    # conversion to MCMCChains.Chains (provided by FlexiChains' MCMCChains extension)
    mcmc_chain = MCMCChains.Chains(hmc_chain)
    @test mcmc_chain isa MCMCChains.Chains
    @test Set([:alpha, :beta, :sigma, :gen_quant]) ⊆ Set(names(mcmc_chain, :parameters))
    for (sym, vn) in (
        (:alpha, @varname(alpha)),
        (:beta, @varname(beta)),
        (:sigma, @varname(sigma)),
        (:gen_quant, @varname(gen_quant)),
    )
        @test mean(mcmc_chain[sym]) ≈ hmc_means[vn] atol = 1e-10
    end

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
    @test Set(FlexiChains.parameters(mh_chain)) ==
        Set([@varname(sigma), @varname(beta), @varname(alpha), @varname(gen_quant)])
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
    mu_draws = hmc_chain[@varname(mu[1:3]), stack = false]
    @test length(mu_draws) == 10
    @test all(v -> v isa AbstractVector && length(v) == 3, mu_draws)
    # each iteration stores its own array copy, not a single reused buffer
    @test allunique(map(objectid, mu_draws))

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

    @testset "multi-chain sampling with MCMCThreads" begin
        model_def = @bugs begin
            for i in 1:N
                y[i] ~ dnorm(mu[i], tau)
                mu[i] = alpha + beta * x[i]
            end
            alpha ~ dnorm(0, 0.01)
            beta ~ dnorm(0, 0.01)
            sigma ~ dunif(0, 10)
            tau = pow(sigma, -2)
        end
        data = (
            N=10,
            x=[0.0, 1.11, 2.22, 3.33, 4.44, 5.56, 6.67, 7.78, 8.89, 10.0],
            y=[1.58, 4.80, 7.10, 8.86, 11.73, 14.52, 18.22, 18.73, 21.04, 22.93],
        )
        # compile=false for thread safety with ReverseDiff
        ad_model = compile(model_def, data, (;); adtype=AutoReverseDiff(; compile=false))
        D = LogDensityProblems.dimension(ad_model)
        n_samples, n_adapts, n_chains = 200, 100, 2

        chain = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(11),
            ad_model,
            NUTS(0.8),
            MCMCThreads(),
            n_samples,
            n_chains;
            progress=false,
            chain_type=VNChain,
            n_adapts=n_adapts,
            init_params=[rand(StableRNG(i), D) for i in 1:n_chains],
            discard_initial=n_adapts,
        )
        # per-chain results are concatenated into a single VNChain along the chain dim
        @test chain isa VNChain
        @test size(chain) == (n_samples, n_chains)
        @test FlexiChains.nchains(chain) == n_chains
        @test Set(FlexiChains.parameters(chain)) ==
            Set([@varname(sigma), @varname(beta), @varname(alpha)])
        per_chain_means = mean(chain; dims=:iter)
        @test length(per_chain_means[@varname(alpha)]) == n_chains
        @test all(isfinite, per_chain_means[@varname(alpha)])
    end

    @testset "discard_initial and thinning set iter_indices" begin
        model_def = @bugs begin
            mu ~ dnorm(0, 1)
            y ~ dnorm(mu, 1)
        end
        ad_model = compile(
            model_def, (; y=1.0), (;); adtype=AutoReverseDiff(; compile=true)
        )
        D = LogDensityProblems.dimension(ad_model)
        n_samples, n_adapts, thin = 20, 50, 3

        chain = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(7),
            ad_model,
            NUTS(0.8),
            n_samples;
            progress=false,
            chain_type=VNChain,
            n_adapts=n_adapts,
            init_params=rand(StableRNG(1), D),
            discard_initial=n_adapts,
            thinning=thin,
        )
        @test size(chain) == (n_samples, 1)
        @test collect(FlexiChains.iter_indices(chain)) ==
            collect(range(n_adapts + 1; step=thin, length=n_samples))
    end

    @testset "gradient model with MH and chain_type=VNChain" begin
        model_def = @bugs begin
            mu ~ dnorm(0, 1)
            y ~ dnorm(mu, 1)
        end
        # sampling a gradient-wrapped model with MH exercises the BUGSModelWithGradient bundle
        ad_model = compile(
            model_def, (; y=1.0), (;); adtype=AutoReverseDiff(; compile=true)
        )
        D = LogDensityProblems.dimension(ad_model)

        chain = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(9),
            ad_model,
            RWMH(MvNormal(zeros(D), I)),
            500;
            progress=false,
            chain_type=VNChain,
            init_params=rand(StableRNG(1), D),
            discard_initial=200,
        )
        @test chain isa VNChain
        @test @varname(mu) in FlexiChains.parameters(chain)
        @test FlexiChains.get_name.(FlexiChains.extras(chain)) == [:lp]
    end

    @testset "auto-marginalization with chain_type=VNChain" begin
        mixture_def = @bugs begin
            w[1] = 0.3
            w[2] = 0.7
            mu[1] ~ Normal(-2, 1)
            mu[2] ~ Normal(2, 1)
            sigma[1] ~ Exponential(1)
            sigma[2] ~ Exponential(1)
            for i in 1:N
                z[i] ~ Categorical(w[1:2])
                y[i] ~ Normal(mu[z[i]], sigma[z[i]])
            end
        end
        N = 40
        rng = StableRNG(1234)
        z_obs = Vector{Union{Int,Missing}}(undef, N)
        z_full = Vector{Int}(undef, N)
        for i in 1:10
            z_full[i] = 1
            z_obs[i] = 1
        end
        for i in (N - 9):N
            z_full[i] = 2
            z_obs[i] = 2
        end
        for i in 11:(N - 10)
            z_full[i] = rand(rng, Categorical([0.3, 0.7]))
            z_obs[i] = missing
        end
        y = [rand(rng, Normal([-2.0, 2.0][z_full[i]], 1.0)) for i in 1:N]
        model = set_evaluation_mode(
            settrans(compile(mixture_def, (; N=N, y=y, z=z_obs)), true),
            UseAutoMarginalization(),
        )
        ad_model = BUGSModelWithGradient(model, AutoForwardDiff())

        chain = Base.invokelatest(
            AbstractMCMC.sample,
            rng,
            ad_model,
            NUTS(0.65),
            200;
            progress=false,
            chain_type=VNChain,
            n_adapts=100,
            init_params=getparams(model),
            discard_initial=100,
        )
        @test chain isa VNChain
        # only the continuous parameters survive; discrete z is marginalized out
        @test Set(FlexiChains.parameters(chain)) == Set([
            @varname(mu[1]), @varname(mu[2]), @varname(sigma[1]), @varname(sigma[2])
        ])
        @test !any(p -> AbstractPPL.getsym(p) == :z, FlexiChains.parameters(chain))
    end
end
