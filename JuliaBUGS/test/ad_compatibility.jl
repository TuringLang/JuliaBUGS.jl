@testset "AD Backend Compatibility" begin
    # Use a simpler model for testing AD compatibility
    # (similar to existing tests in JuliaBUGSAdvancedHMCExt.jl)
    model_def = @bugs begin
        mu ~ dnorm(0, 1)
        for i in 1:N
            y[i] ~ dnorm(mu, 1)
        end
    end
    data = (N=5, y=[1.0, 2.0, 1.5, 2.5, 1.8])

    @testset "UseGraph mode" begin
        model = compile(model_def, data)
        @test model.evaluation_mode isa JuliaBUGS.UseGraph

        x = JuliaBUGS.getparams(model)

        @testset "AutoReverseDiff" begin
            grad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoReverseDiff())
            @test grad_model isa JuliaBUGS.BUGSModelWithGradient
            @test grad_model.base_model.evaluation_mode isa JuliaBUGS.UseGraph

            # Test gradient computation works
            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, x)
            @test isfinite(logp)
            @test all(isfinite, grad)
        end

        @testset "AutoForwardDiff" begin
            grad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoForwardDiff())
            @test grad_model isa JuliaBUGS.BUGSModelWithGradient
            @test grad_model.base_model.evaluation_mode isa JuliaBUGS.UseGraph

            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, x)
            @test isfinite(logp)
            @test all(isfinite, grad)
        end

        @testset "Gradient consistency across backends" begin
            rd_model = JuliaBUGS.BUGSModelWithGradient(model, AutoReverseDiff())
            fd_model = JuliaBUGS.BUGSModelWithGradient(model, AutoForwardDiff())

            logp_rd, grad_rd = LogDensityProblems.logdensity_and_gradient(rd_model, x)
            logp_fd, grad_fd = LogDensityProblems.logdensity_and_gradient(fd_model, x)

            @test logp_rd ≈ logp_fd
            @test grad_rd ≈ grad_fd rtol = 1e-6
        end
    end

    @testset "UseGeneratedLogDensityFunction mode" begin
        model = compile(model_def, data)
        model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())
        @test model.evaluation_mode isa JuliaBUGS.UseGeneratedLogDensityFunction

        x = JuliaBUGS.getparams(model)

        @testset "AutoReverseDiff - should warn and switch to UseGraph" begin
            grad_model = @test_warn "does not support mutation" JuliaBUGS.BUGSModelWithGradient(
                model, AutoReverseDiff()
            )
            @test grad_model.base_model.evaluation_mode isa JuliaBUGS.UseGraph

            # Should still work after switching
            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, x)
            @test isfinite(logp)
            @test all(isfinite, grad)
        end

        @testset "AutoForwardDiff - should switch to UseGraph" begin
            # Note: Warning is suppressed due to maxlog=1 (already shown in ReverseDiff test)
            grad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoForwardDiff())
            @test grad_model.base_model.evaluation_mode isa JuliaBUGS.UseGraph

            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, x)
            @test isfinite(logp)
            @test all(isfinite, grad)
        end

        @testset "AutoMooncake - should work without warning" begin
            grad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
            @test grad_model.base_model.evaluation_mode isa JuliaBUGS.UseGeneratedLogDensityFunction

            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, x)
            @test isfinite(logp)
            @test all(isfinite, grad)
        end
    end

    @testset "compile with adtype parameter" begin
        @testset "AutoReverseDiff" begin
            grad_model = compile(model_def, data; adtype=AutoReverseDiff())
            @test grad_model isa JuliaBUGS.BUGSModelWithGradient

            x = JuliaBUGS.getparams(grad_model.base_model)
            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, x)
            @test isfinite(logp)
            @test all(isfinite, grad)
        end

        @testset "AutoForwardDiff" begin
            grad_model = compile(model_def, data; adtype=AutoForwardDiff())
            @test grad_model isa JuliaBUGS.BUGSModelWithGradient

            x = JuliaBUGS.getparams(grad_model.base_model)
            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, x)
            @test isfinite(logp)
            @test all(isfinite, grad)
        end
    end
end
