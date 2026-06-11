using JuliaBUGS: @bugs, compile, settrans, getparams, initialize!
using JuliaBUGS.Model:
    set_evaluation_mode,
    UseAutoMarginalization,
    evaluate_and_sample_with_marginalization_values!!

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
    # Use BUGSModelWithGradient to get proper parameter naming in chains
    ad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoForwardDiff())

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

@testset "Ancestral sampler continuous params reconstructed" begin
    # Verify continuous parameters in the returned env match the input vector
    mixture_def = @bugs begin
        w[1] = 0.3
        w[2] = 0.7
        mu[1] ~ Normal(-2, 5)
        mu[2] ~ Normal(2, 5)
        sigma[1] ~ Exponential(1)
        sigma[2] ~ Exponential(1)
        for i in 1:N
            z[i] ~ Categorical(w[1:2])
            y[i] ~ Normal(mu[z[i]], sigma[z[i]])
        end
    end

    data = (N=4, y=[-1.5, 2.3, -2.1, 1.8])
    model = compile(mixture_def, data)
    model = settrans(model, true)
    model = set_evaluation_mode(model, UseAutoMarginalization())

    test_params = [0.0, 0.0, 2.0, -2.0]

    env = Base.invokelatest(
        evaluate_and_sample_with_marginalization_values!!, model, test_params
    )

    @test isapprox(AbstractPPL.getvalue(env, @varname(sigma[1])), 1.0; atol=1e-10)
    @test isapprox(AbstractPPL.getvalue(env, @varname(sigma[2])), 1.0; atol=1e-10)
    @test isapprox(AbstractPPL.getvalue(env, @varname(mu[2])), 2.0; atol=1e-10)
    @test isapprox(AbstractPPL.getvalue(env, @varname(mu[1])), -2.0; atol=1e-10)
end

@testset "Discrete latents in valid support" begin
    # Verify each sampled z[i] is in the Categorical support {1, 2}
    mixture_def = @bugs begin
        w[1] = 0.3
        w[2] = 0.7
        mu[1] ~ Normal(-2, 5)
        mu[2] ~ Normal(2, 5)
        sigma[1] ~ Exponential(1)
        sigma[2] ~ Exponential(1)
        for i in 1:N
            z[i] ~ Categorical(w[1:2])
            y[i] ~ Normal(mu[z[i]], sigma[z[i]])
        end
    end

    data = (N=4, y=[-1.5, 2.3, -2.1, 1.8])
    model = compile(mixture_def, data)
    model = settrans(model, true)
    model = set_evaluation_mode(model, UseAutoMarginalization())

    test_params = [0.0, 0.0, 2.0, -2.0]

    env = Base.invokelatest(
        evaluate_and_sample_with_marginalization_values!!, model, test_params
    )

    @test AbstractPPL.getvalue(env, @varname(z[1])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[2])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[3])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[4])) in (1, 2)
end

@testset "Statistical correctness" begin
    # Single discrete latent with all fixed parameters.
    simple_def = @bugs begin
        w[1] = 0.3
        w[2] = 0.7
        mu[1] = -3.0
        mu[2] = 3.0
        sigma = 1.0
        z ~ Categorical(w[1:2])
        y ~ Normal(mu[z], sigma)
    end

    data = (y=2.5,)
    model = compile(simple_def, data)
    model = settrans(model, true)
    model = set_evaluation_mode(model, UseAutoMarginalization())

    test_params = Float64[]

    log_p1 = log(0.3) + logpdf(Normal(-3.0, 1.0), 2.5)
    log_p2 = log(0.7) + logpdf(Normal(3.0, 1.0), 2.5)
    p_z2_analytical = exp(log_p2) / (exp(log_p1) + exp(log_p2))

    n_samples = 5000
    z2_count = sum(
        AbstractPPL.getvalue(
            Base.invokelatest(
                evaluate_and_sample_with_marginalization_values!!, model, test_params
            ),
            @varname(z),
        ) == 2 for _ in 1:n_samples
    )
    p_z2_empirical = z2_count / n_samples

    @test isapprox(p_z2_empirical, p_z2_analytical; atol=0.03)
end

@testset "Deterministic nodes recomputed" begin
    # Deterministic node mean_val[i] = mu[z[i]] depends on the sampled z.
    det_def = @bugs begin
        w[1] = 0.5
        w[2] = 0.5
        mu[1] = -5.0
        mu[2] = 5.0
        sigma = 1.0
        for i in 1:N
            z[i] ~ Categorical(w[1:2])
            mean_val[i] = mu[z[i]]
            y[i] ~ Normal(mean_val[i], sigma)
        end
    end

    data = (N=2, y=[-4.5, 4.8])
    model = compile(det_def, data)
    model = settrans(model, true)
    model = set_evaluation_mode(model, UseAutoMarginalization())

    test_params = Float64[]

    env = Base.invokelatest(
        evaluate_and_sample_with_marginalization_values!!, model, test_params
    )

    z1 = AbstractPPL.getvalue(env, @varname(z[1]))
    z2 = AbstractPPL.getvalue(env, @varname(z[2]))
    mv1 = AbstractPPL.getvalue(env, @varname(mean_val[1]))
    mv2 = AbstractPPL.getvalue(env, @varname(mean_val[2]))

    @test mv1 == (z1 == 1 ? -5.0 : 5.0)
    @test mv2 == (z2 == 1 ? -5.0 : 5.0)
end

@testset "Partially observed z" begin
    # Observed values must be preserved, unobserved must be in valid support.
    mixture_def = @bugs begin
        w[1] = 0.3
        w[2] = 0.7
        mu[1] ~ Normal(-2, 5)
        mu[2] ~ Normal(2, 5)
        sigma ~ Exponential(1)
        for i in 1:N
            z[i] ~ Categorical(w[1:2])
            y[i] ~ Normal(mu[z[i]], sigma)
        end
    end

    data = (N=4, y=[1.0, 2.0, -1.0, 3.0], z=[2, missing, 1, missing])
    model = compile(mixture_def, data)
    model = settrans(model, true)
    model = set_evaluation_mode(model, UseAutoMarginalization())

    test_params = [0.0, 2.0, -2.0]

    env = Base.invokelatest(
        evaluate_and_sample_with_marginalization_values!!, model, test_params
    )

    @test AbstractPPL.getvalue(env, @varname(z[1])) == 2
    @test AbstractPPL.getvalue(env, @varname(z[3])) == 1

    @test AbstractPPL.getvalue(env, @varname(z[2])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[4])) in (1, 2)
end

@testset "Joint HMM sampling" begin
    # HMM with well-separated emissions.
    hmm_def = @bugs begin
        pi[1] = 0.5
        pi[2] = 0.5
        trans[1, 1] = 0.9
        trans[1, 2] = 0.1
        trans[2, 1] = 0.1
        trans[2, 2] = 0.9
        mu[1] = 0.0
        mu[2] = 5.0
        sigma = 1.0

        z[1] ~ Categorical(pi[1:2])
        for t in 2:T
            p[t, 1] = trans[z[t - 1], 1]
            p[t, 2] = trans[z[t - 1], 2]
            z[t] ~ Categorical(p[t, :])
        end

        for t in 1:T
            y[t] ~ Normal(mu[z[t]], sigma)
        end
    end

    data = (T=4, y=[0.1, -0.2, 4.9, 5.1])
    model = compile(hmm_def, data)
    model = settrans(model, true)
    model = set_evaluation_mode(model, UseAutoMarginalization())

    test_params = Float64[]

    env = Base.invokelatest(
        evaluate_and_sample_with_marginalization_values!!, model, test_params
    )
    @test AbstractPPL.getvalue(env, @varname(z[1])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[2])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[3])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[4])) in (1, 2)

    n_samples = 500
    z1_is_1 = 0
    z4_is_2 = 0
    for _ in 1:n_samples
        env = Base.invokelatest(
            evaluate_and_sample_with_marginalization_values!!, model, test_params
        )
        AbstractPPL.getvalue(env, @varname(z[1])) == 1 && (z1_is_1 += 1)
        AbstractPPL.getvalue(env, @varname(z[4])) == 2 && (z4_is_2 += 1)
    end
    @test z1_is_1 / n_samples > 0.8
    @test z4_is_2 / n_samples > 0.8
end

@testset "No discrete variables" begin
    # Should reconstruct params without error
    continuous_def = @bugs begin
        mu ~ Normal(0, 10)
        sigma ~ Exponential(1)
        for i in 1:N
            y[i] ~ Normal(mu, sigma)
        end
    end

    data = (N=3, y=[1.0, 2.0, 3.0])
    model = compile(continuous_def, data)
    model = settrans(model, true)
    model = set_evaluation_mode(model, UseAutoMarginalization())

    test_params = [0.0, 2.0]

    env = Base.invokelatest(
        evaluate_and_sample_with_marginalization_values!!, model, test_params
    )

    @test isapprox(AbstractPPL.getvalue(env, @varname(sigma)), 1.0; atol=1e-10)
    @test isapprox(AbstractPPL.getvalue(env, @varname(mu)), 2.0; atol=1e-10)
end

@testset "GQ bypass" begin
    gq_def = @bugs begin
        w[1] = 0.5
        w[2] = 0.5
        mu[1] ~ Normal(0, 5)
        mu[2] ~ Normal(0, 5)
        sigma ~ Exponential(1)
        for i in 1:N
            z[i] ~ Categorical(w[1:2])
            y[i] ~ Normal(mu[z[i]], sigma)
        end
        y_pred ~ Normal(mu[1], sigma)
    end

    data = (N=3, y=[1.0, -1.0, 2.0])
    model = compile(gq_def, data)
    model = settrans(model, true)
    model = set_evaluation_mode(model, UseAutoMarginalization())

    test_params = [0.0, 1.0, -1.0]

    logp = Base.invokelatest(LogDensityProblems.logdensity, model, test_params)
    @test isfinite(logp)

    env = Base.invokelatest(
        evaluate_and_sample_with_marginalization_values!!, model, test_params
    )

    @test isapprox(AbstractPPL.getvalue(env, @varname(sigma)), 1.0; atol=1e-10)
    @test isapprox(AbstractPPL.getvalue(env, @varname(mu[1])), -1.0; atol=1e-10)
    @test isapprox(AbstractPPL.getvalue(env, @varname(mu[2])), 1.0; atol=1e-10)
    @test AbstractPPL.getvalue(env, @varname(z[1])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[2])) in (1, 2)
    @test AbstractPPL.getvalue(env, @varname(z[3])) in (1, 2)
end
