function _logjoint(model::JuliaBUGS.BUGSModel)
    _, log_densities = JuliaBUGS.evaluate_with_env!!(model; transformed=model.transformed)
    return log_densities.tempered_logjoint
end

function verify_log_densities_structure(log_densities)
    @test isa(log_densities, NamedTuple)
    # @test length(log_densities) == 3
    @test haskey(log_densities, :logprior)
    @test haskey(log_densities, :loglikelihood)
    @test haskey(log_densities, :tempered_logjoint)
end

function test_bugs_model_log_density(
    model_example, expected_untransformed, expected_transformed=expected_untransformed
)
    (; model_def, data, inits) = model_example
    transformed_model = compile(model_def, data, inits)
    untransformed_model = JuliaBUGS.settrans(transformed_model, false)

    # Allow world age to advance by calling the functions in a separate evaluation
    Base.invokelatest() do
        @test _logjoint(untransformed_model) ≈ expected_untransformed rtol = 1E-6
        @test _logjoint(transformed_model) ≈ expected_transformed rtol = 1E-6

        @test LogDensityProblems.logdensity(
            transformed_model, JuliaBUGS.getparams(transformed_model)
        ) ≈ expected_transformed rtol = 1E-6
        @test LogDensityProblems.logdensity(
            untransformed_model, JuliaBUGS.getparams(untransformed_model)
        ) ≈ expected_untransformed rtol = 1E-6
    end
end

@testset "evaluate_with_rng!! - controlling sampling behavior" begin
    model_def = @bugs begin
        x ~ Normal(0, 1)
        y ~ Normal(x, 1)
    end

    data = (; y=1.0)
    model = compile(model_def, data, (; x=1.0))

    eval_env, log_densities = JuliaBUGS.evaluate_with_rng!!(
        Random.default_rng(), model; sample_all=false
    )
    @test eval_env.y == 1.0
    @test eval_env.x != 1.0

    eval_env, log_densities = JuliaBUGS.evaluate_with_rng!!(
        Random.default_rng(), model; sample_all=true
    )
    @test eval_env.y != 1.0
    @test eval_env.x != 1.0

    verify_log_densities_structure(log_densities)
end

@testset "evaluate_with_rng!! - environment modification" begin
    unid_model_def = @bugs begin
        for i in 1:2
            p[i] ~ dunif(0, 1)
        end
        p_prod = p[1] * p[2]
        n_heads ~ dbin(p_prod, n_flips)
    end
    data = (; n_flips=100000)
    rng = MersenneTwister(123)

    model = compile(unid_model_def, data)
    eval_env, log_densities = JuliaBUGS.evaluate_with_rng!!(rng, model)
    @test eval_env.p_prod == eval_env.p[1] * eval_env.p[2]
    @test isa(eval_env.p_prod, Float64)
    @test 0 <= eval_env.p_prod <= 1
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

        _, log_densities = JuliaBUGS.evaluate_with_values!!(
            model, params; temperature=2.0, transformed=true
        )

        @test log_densities.logprior ≈ log_prior_true rtol = 1E-6
        @test log_densities.loglikelihood ≈ log_likelihood_true rtol = 1E-6
        @test log_densities.tempered_logjoint ≈ log_prior_true + 2.0 * log_likelihood_true rtol =
            1E-6
    end
end

@testset "Log density" begin
    @testset "Log density of distributions" begin
        @testset "dbin (Binomial)" begin
            dist = dbin(0.1, 10)
            b = Bijectors.bijector(dist)
            test_θ_transformed = 10
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            model_def = @bugs begin
                a ~ dbin(0.1, 10)
            end
            transformed_model = compile(model_def, NamedTuple(), (a=test_θ,))
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end

        @testset "dgamma (Gamma)" begin
            dist = dgamma(0.001, 0.001)
            b = Bijectors.bijector(dist)
            test_θ_transformed = 10
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            model_def = @bugs begin
                a ~ dgamma(0.001, 0.001)
            end
            transformed_model = compile(model_def, NamedTuple(), (a=test_θ,))
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end

        @testset "ddirich (Dirichlet)" begin
            # create valid test input
            alpha = rand(10)
            dist = ddirich(alpha)
            b = Bijectors.bijector(dist)
            test_θ_transformed = rand(9)
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            model_def = @bugs begin
                x[1:10] ~ ddirich(alpha[1:10])
            end
            transformed_model = compile(model_def, (alpha=alpha,), (x=test_θ,))
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end

        @testset "dwish (Wishart)" begin
            # create valid test input
            scale_matrix = randn(10, 10)
            scale_matrix = scale_matrix * transpose(scale_matrix)  # Ensuring positive-definiteness
            degrees_of_freedom = 12

            dist = dwish(scale_matrix, degrees_of_freedom)
            b = Bijectors.bijector(dist)
            test_θ_transformed = rand(55)
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            model_def = @bugs begin
                x[1:10, 1:10] ~ dwish(scale_matrix[:, :], degrees_of_freedom)
            end
            transformed_model = compile(
                model_def,
                (degrees_of_freedom=degrees_of_freedom, scale_matrix=scale_matrix),
                (x=test_θ,),
            )
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end

        @testset "lkj (LKJ)" begin
            dist = LKJ(10, 0.5)
            b = Bijectors.bijector(dist)
            test_θ_transformed = rand(45)
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            model_def = @bugs begin
                x[1:10, 1:10] ~ LKJ(10, 0.5)
            end
            transformed_model = compile(model_def, NamedTuple(), (x=test_θ,))
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            @test LogDensityProblems.dimension(untransformed_model) == 100
            @test LogDensityProblems.dimension(transformed_model) == 45

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end
    end
end

@testset "Log density of BUGS models" begin
    @testset "rats" begin
        test_bugs_model_log_density(
            JuliaBUGS.BUGSExamples.VOLUME_1.rats, -174029.38703951868
        )
    end

    @testset "blockers" begin
        test_bugs_model_log_density(
            JuliaBUGS.BUGSExamples.VOLUME_1.blockers, -8418.416388326123
        )
    end

    @testset "bones" begin
        test_bugs_model_log_density(
            JuliaBUGS.BUGSExamples.VOLUME_1.bones, -161.6492002285034
        )
    end

    @testset "dogs" begin
        test_bugs_model_log_density(
            JuliaBUGS.BUGSExamples.VOLUME_1.dogs, -1243.188922285352, -1243.3996613167667
        )
    end
end

@testset "evaluate_with_env!!" begin
    @testset "Basic functionality" begin
        model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
            z = x + y
        end

        data = (; y=2.0)
        model = compile(model_def, data, (; x=1.5))

        eval_env, log_densities = JuliaBUGS.evaluate_with_env!!(model)

        @test eval_env.x == 1.5
        @test eval_env.y == 2.0
        @test eval_env.z == 3.5

        verify_log_densities_structure(log_densities)

        expected_logprior = logpdf(Normal(0, 1), 1.5)
        expected_loglikelihood = logpdf(Normal(1.5, 1), 2.0)
        @test log_densities.logprior ≈ expected_logprior
        @test log_densities.loglikelihood ≈ expected_loglikelihood
        @test log_densities.tempered_logjoint ≈ expected_logprior + expected_loglikelihood
    end

    @testset "Custom evaluation environment" begin
        model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
        end

        data = (; y=2.0)
        model = compile(model_def, data, (; x=1.0))

        custom_env = JuliaBUGS.BangBang.setindex!!(model.evaluation_env, 3.0, @varname(x))
        eval_env, log_densities = JuliaBUGS.evaluate_with_env!!(model, custom_env)

        @test eval_env.x == 3.0
        @test eval_env.y == 2.0

        expected_logprior = logpdf(Normal(0, 1), 3.0)
        expected_loglikelihood = logpdf(Normal(3.0, 1), 2.0)
        @test log_densities.logprior ≈ expected_logprior
        @test log_densities.loglikelihood ≈ expected_loglikelihood
    end
end

@testset "evaluate_with_values!!" begin
    @testset "Basic functionality - transformed space" begin
        model_def = @bugs begin
            sigma ~ InverseGamma(2, 3)
            mu ~ Normal(0, sigma)
            y ~ Normal(mu, sigma)
        end

        data = (; y=1.0)
        model = compile(model_def, data)

        transformed_vals = [0.5, 0.0]
        eval_env, log_densities = JuliaBUGS.evaluate_with_values!!(
            model, transformed_vals; transformed=true
        )

        b = Bijectors.bijector(InverseGamma(2, 3))
        sigma_untransformed = Bijectors.inverse(b)(0.5)
        @test eval_env.sigma ≈ sigma_untransformed
        @test eval_env.mu ≈ 0.0
        @test eval_env.y ≈ 1.0

        @test isa(log_densities.logprior, Real)
        @test isa(log_densities.loglikelihood, Real)
        @test log_densities.tempered_logjoint ≈
            log_densities.logprior + log_densities.loglikelihood
    end

    @testset "Basic functionality - untransformed space" begin
        model_def = @bugs begin
            sigma ~ InverseGamma(2, 3)
            mu ~ Normal(0, sigma)
            y ~ Normal(mu, sigma)
        end

        data = (; y=1.0)
        model = compile(model_def, data)

        untransformed_vals = [1.5, 0.5]
        eval_env, log_densities = JuliaBUGS.evaluate_with_values!!(
            model, untransformed_vals; transformed=false
        )

        @test eval_env.sigma ≈ 1.5
        @test eval_env.mu ≈ 0.5
        @test eval_env.y ≈ 1.0

        expected_logprior = logpdf(InverseGamma(2, 3), 1.5) + logpdf(Normal(0, 1.5), 0.5)
        expected_loglikelihood = logpdf(Normal(0.5, 1.5), 1.0)
        @test log_densities.logprior ≈ expected_logprior
        @test log_densities.loglikelihood ≈ expected_loglikelihood
    end
end

@testset "Temperature parameter" begin
    model_def = @bugs begin
        x ~ Normal(0, 1)
        y ~ Normal(x, 1)
    end

    data = (; y=2.0)
    model = compile(model_def, data, (; x=1.0))

    for temp in [0.5, 1.0, 2.0]
        _, log_densities = JuliaBUGS.evaluate_with_env!!(model; temperature=temp)

        expected_logprior = logpdf(Normal(0, 1), 1.0)
        expected_loglikelihood = logpdf(Normal(1.0, 1), 2.0)
        expected_tempered = expected_logprior + temp * expected_loglikelihood

        @test log_densities.logprior ≈ expected_logprior
        @test log_densities.loglikelihood ≈ expected_loglikelihood
        @test log_densities.tempered_logjoint ≈ expected_tempered
    end
end

@testset "Transformed vs Untransformed behavior" begin
    @testset "With constrained distributions" begin
        model_def = @bugs begin
            tau ~ dgamma(0.001, 0.001)
            sigma = 1 / sqrt(tau)
            y ~ dnorm(0, tau)
        end

        data = (; y=1.0)
        model = compile(model_def, data, (; tau=2.0))

        # Get parameters in both spaces
        params_transformed = JuliaBUGS.getparams(model)

        # Convert to untransformed space
        b = Bijectors.bijector(dgamma(0.001, 0.001))
        tau_untransformed = Bijectors.inverse(b)(params_transformed[1])
        params_untransformed = [tau_untransformed]

        # Test that evaluate_with_values!! correctly handles transformed flag
        # When transformed=true, it expects transformed parameters
        env1, ld1 = JuliaBUGS.evaluate_with_values!!(
            model, params_transformed; transformed=true
        )

        # When transformed=false, it expects untransformed parameters
        env2, ld2 = JuliaBUGS.evaluate_with_values!!(
            model, params_untransformed; transformed=false
        )

        # The evaluation environments should have the same tau value
        @test env1.tau ≈ env2.tau rtol = 1e-6

        # Test that log density computation respects model.transformed setting
        # For a transformed model, evaluate!! should use transformed space
        @test model.transformed == true
        _, logp_trans = AbstractPPL.evaluate!!(model, params_transformed)

        # For an untransformed model, evaluate!! should use untransformed space
        model_untrans = JuliaBUGS.settrans(model, false)
        @test model_untrans.transformed == false
        _, logp_untrans = AbstractPPL.evaluate!!(model_untrans, params_untransformed)

        # The log densities will be different due to Jacobian adjustment
        # But both should be valid log densities (finite)
        @test isfinite(logp_trans)
        @test isfinite(logp_untrans)
    end
end

@testset "Complex models with multiple parameter types" begin
    @testset "Model with array parameters" begin
        model_def = @bugs begin
            for i in 1:3
                alpha[i] ~ Normal(0, 1)
            end
            sigma ~ InverseGamma(2, 3)
            for i in 1:3
                y[i] ~ Normal(alpha[i], sigma)
            end
        end

        data = (; y=[1.0, 2.0, 3.0])
        model = compile(model_def, data)

        rng = MersenneTwister(42)
        eval_env, log_densities = JuliaBUGS.evaluate_with_rng!!(
            rng, model; sample_all=false
        )

        @test length(eval_env.alpha) == 3
        @test isa(eval_env.sigma, Real)
        @test eval_env.y == [1.0, 2.0, 3.0]

        @test log_densities.logprior < 0
        @test log_densities.loglikelihood < 0
        @test log_densities.tempered_logjoint ≈
            log_densities.logprior + log_densities.loglikelihood
    end
end

@testset "Edge cases" begin
    @testset "Model with only priors" begin
        model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
        end

        model = compile(model_def, (;))

        rng = MersenneTwister(123)
        eval_env, log_densities = JuliaBUGS.evaluate_with_rng!!(rng, model)

        @test log_densities.loglikelihood == 0.0
        @test log_densities.logprior < 0
        @test log_densities.tempered_logjoint == log_densities.logprior
    end

    @testset "Model with deterministic nodes" begin
        model_def = @bugs begin
            a ~ Normal(0, 1)
            b ~ Normal(0, 1)
            c = a + b
            d = c * 2
            y ~ Normal(d, 1)
        end

        data = (; y=3.0)
        model = compile(model_def, data, (; a=1.0, b=0.5))

        eval_env, log_densities = JuliaBUGS.evaluate_with_env!!(model)

        @test eval_env.c ≈ 1.5
        @test eval_env.d ≈ 3.0

        expected_logprior = logpdf(Normal(0, 1), 1.0) + logpdf(Normal(0, 1), 0.5)
        expected_loglikelihood = logpdf(Normal(3.0, 1), 3.0)
        @test log_densities.logprior ≈ expected_logprior
        @test log_densities.loglikelihood ≈ expected_loglikelihood
    end
end

@testset "AbstractPPL.evaluate!! interface" begin
    model_def = @bugs begin
        x ~ Normal(0, 1)
        y ~ Normal(x, 1)
    end

    data = (; y=2.0)
    model = compile(model_def, data, (; x=1.0))

    @testset "evaluate!! with RNG" begin
        rng = MersenneTwister(42)
        eval_env, logp = AbstractPPL.evaluate!!(rng, model)

        @test isa(eval_env, NamedTuple)
        @test isa(logp, Real)
        @test haskey(eval_env, :x)
        @test haskey(eval_env, :y)
    end

    @testset "evaluate!! without arguments" begin
        eval_env, logp = AbstractPPL.evaluate!!(model)

        @test eval_env.x == 1.0
        @test eval_env.y == 2.0
        @test isa(logp, Real)
    end

    @testset "evaluate!! with values" begin
        vals = [0.5]
        eval_env, logp = AbstractPPL.evaluate!!(model, vals)

        @test eval_env.x ≈ 0.5
        @test eval_env.y == 2.0
        @test isa(logp, Real)
    end
end
