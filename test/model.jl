@testset "serialization" begin
    (; model_def, data) = JuliaBUGS.BUGSExamples.rats
    model = compile(model_def, data)
    serialize("m.jls", model)
    deserialized = deserialize("m.jls")
    @testset "test values are correctly restored" begin
        for vn in MetaGraphsNext.labels(model.g)
            @test isequal(
                get(model.evaluation_env, vn), get(deserialized.evaluation_env, vn)
            )
        end

        @test model.transformed == deserialized.transformed
        @test model.untransformed_param_length == deserialized.untransformed_param_length
        @test model.transformed_param_length == deserialized.transformed_param_length
        @test all(
            model.untransformed_var_lengths[k] == deserialized.untransformed_var_lengths[k]
            for k in keys(model.untransformed_var_lengths)
        )
        @test all(
            model.transformed_var_lengths[k] == deserialized.transformed_var_lengths[k] for
            k in keys(model.transformed_var_lengths)
        )
        @test Set(model.parameters) == Set(deserialized.parameters)
        # skip testing g
        @test model.model_def == deserialized.model_def
    end
end

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

    model = compile(unid_model_def, data)
    eval_env, logp = JuliaBUGS.evaluate!!(rng, model)
    @test eval_env.p_prod == eval_env.p[1] * eval_env.p[2]
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
