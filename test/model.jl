@testset "controlling sampling behavior for conditioned variables" begin
    model_def = @bugs begin
        x ~ Normal(0, 1)
        y ~ Normal(x, 1)
    end

    data = (; y=1.0)
    model = compile(model_def, data, (; x=1.0))

    eval_env, logp = JuliaBUGS.evaluate!!(Random.default_rng(), model; sample_all=false)
    @test eval_env.y == 1.0
    @test eval_env.x != 1.0

    eval_env, logp = JuliaBUGS.evaluate!!(Random.default_rng(), model; sample_all=true)
    @test eval_env.y != 1.0
    @test eval_env.x != 1.0
end

@testset "`evaluate!!` is actually modifying returned `evaluation_env`" begin
    # unidentifiable coin-toss model
    unid_model_def = @bugs begin
        for i in 1:2
            p[i] ~ dunif(0, 1)
        end
        p_prod = p[1] * p[2]
        n_heads ~ dbin(p_prod, n_flips)
    end
    data = (; n_flips=100000)
    n_sim = 1000
    true_prop = 0.25 # = E[p_prod] = 0.5^2
    rng = MersenneTwister(123)

    # do multiple initializations to check for bug
    for _ in 1:10
        model = compile(unid_model_def, data)
        original_env = deepcopy(model.evaluation_env)

        # simulate flips and compute rate of heads
        heads_rate = mean(
            first(JuliaBUGS.evaluate!!(rng, model)).n_heads / data.n_flips for _ in 1:n_sim
        )

        # compute pvalue for a one-sample test against true proportion
        z_true = (heads_rate - true_prop) / sqrt(true_prop * (1 - true_prop) / n_sim)
        pval_true = 2 * ccdf(Normal(), abs(z_true))

        # compute pvalue for a one-sample test against initial p_prod
        z_alt =
            (heads_rate - original_env.p_prod) /
            sqrt(original_env.p_prod * (1 - original_env.p_prod) / n_sim)
        pval_alt = 2 * ccdf(Normal(), abs(z_alt))

        # check that simulated data is more consistent with true proportion than initial value
        @test pval_true > 0.05 # simulated data consistent with true proportion
        @test pval_alt < 0.05 # simulated data inconsistent with initial value
    end
end

@testset "logprior and loglikelihood" begin
    @testset "Complex model with transformations" begin
        model_def = @bugs begin
            s[1] ~ InverseGamma(2, 3)
            s[2] ~ InverseGamma(2, 3)
            m[1] ~ Normal(0, sqrt(s[1]))
            m[2] ~ Normal(0, sqrt(s[2]))
            x[1:2] ~ MvNormal(m[1:2], Diagonal(s[1:2]))
        end

        data = (; x=[1.0, 2.0])

        model = compile(model_def, data)

        params = rand(4)

        b = Bijectors.bijector(InverseGamma(2, 3))
        b_inv = Bijectors.inverse(b)

        log_prior_true = begin
            # parameter sorted: s[2], m[2], s[1], m[1]
            s1_inversed, logjac1 = Bijectors.with_logabsdet_jacobian(b_inv, params[3])
            s2_inversed, logjac2 = Bijectors.with_logabsdet_jacobian(b_inv, params[1])
            logpdf(InverseGamma(2, 3), s1_inversed) +
            logjac1 +
            logpdf(InverseGamma(2, 3), s2_inversed) +
            logjac2 +
            logpdf(Normal(0, sqrt(s1_inversed)), params[4]) +
            logpdf(Normal(0, sqrt(s2_inversed)), params[2])
        end

        log_likelihood_true = begin
            s1_inversed = b_inv(params[3])
            s2_inversed = b_inv(params[1])
            logpdf(
                MvNormal([params[4], params[2]], Diagonal([s1_inversed, s2_inversed])),
                data.x,
            )
        end

        _, (logprior, loglikelihood, tempered_logjoint) = JuliaBUGS._tempered_evaluate!!(
            model, params; temperature=2.0
        )

        @test logprior ≈ log_prior_true rtol = 1E-6
        @test loglikelihood ≈ log_likelihood_true rtol = 1E-6
        @test tempered_logjoint ≈ log_prior_true + 2.0 * log_likelihood_true rtol = 1E-6
    end
end
