@testset "DomainError handling in logdensity" begin
    @testset "Poisson: negative λ" begin
        model_def = @bugs begin
            alpha ~ dnorm(0.0, 1.0)
            y ~ dpois(alpha)
        end
        data = (y=1,)
        inits = (alpha=1.0,)
        model = compile(model_def, data, inits)

        Base.invokelatest() do
            # Valid parameter: should return finite logdensity
            logp = LogDensityProblems.logdensity(model, [1.0])
            @test isfinite(logp)

            # Invalid parameter: alpha = -1 → Poisson(-1) → DomainError
            # Should return -Inf, not throw
            logp = LogDensityProblems.logdensity(model, [-1.0])
            @test logp == -Inf
        end
    end

    @testset "Binomial: p outside [0, 1]" begin
        model_def = @bugs begin
            theta ~ dnorm(0.5, 1.0)
            y ~ dbin(theta, 10)
        end
        data = (y=3,)
        inits = (theta=0.5,)
        model = compile(model_def, data, inits)

        Base.invokelatest() do
            logp = LogDensityProblems.logdensity(model, [0.5])
            @test isfinite(logp)

            # theta = -0.5 → Binomial(10, -0.5) → DomainError
            logp = LogDensityProblems.logdensity(model, [-0.5])
            @test logp == -Inf
        end
    end

    @testset "Weibull: negative shape" begin
        model_def = @bugs begin
            alpha ~ dnorm(1.0, 1.0)
            y ~ dweib(alpha, 1.0)
        end
        data = (y=1.0,)
        inits = (alpha=1.0,)
        model = compile(model_def, data, inits)

        Base.invokelatest() do
            logp = LogDensityProblems.logdensity(model, [1.0])
            @test isfinite(logp)

            # alpha = -1 → Weibull(-1, 1) → DomainError
            logp = LogDensityProblems.logdensity(model, [-1.0])
            @test logp == -Inf
        end
    end

    @testset "Normal: negative precision (custom BUGS check)" begin
        model_def = @bugs begin
            tau ~ dnorm(1.0, 1.0)
            y ~ dnorm(0.0, tau)
        end
        data = (y=1.0,)
        inits = (tau=1.0,)
        model = compile(model_def, data, inits)

        Base.invokelatest() do
            logp = LogDensityProblems.logdensity(model, [1.0])
            @test isfinite(logp)

            # tau = -1 → dnorm(0, -1) → DomainError (custom throw in BUGSPrimitives)
            logp = LogDensityProblems.logdensity(model, [-1.0])
            @test logp == -Inf
        end
    end

    @testset "logdensity_and_gradient with DomainError" begin
        model_def = @bugs begin
            alpha ~ dnorm(0.0, 1.0)
            y ~ dpois(alpha)
        end
        data = (y=1,)
        inits = (alpha=1.0,)
        model = compile(model_def, data, inits)

        Base.invokelatest() do
            grad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoForwardDiff())

            # Valid parameter
            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, [1.0])
            @test isfinite(logp)
            @test all(isfinite, grad)

            # Invalid parameter: should return (-Inf, NaN gradient), not throw
            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, [-1.0])
            @test logp == -Inf
            @test all(isnan, grad)
        end
    end
end
