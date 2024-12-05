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
