@testset "function generation" begin
    @testset "simple examples" begin
        model_def = @bugs begin
            x ~ dnorm(0, 1)
            y ~ dnorm(x, 1)
            z = x + y
            w ~ dnorm(z, 1)
        end

        model = compile(model_def, (; x=1.0,))
        f_ex = generate_expr(model)
        f = eval(f_ex)
        params = rand(2)
        @test Base.invokelatest(f, model.varinfo.values, params) ≈
            LogDensityProblems.logdensity(model, params) rtol = 1e-6

        model_def = @bugs begin
            x[1:2] ~ dmnorm(zeros(2), eye[1:2, 1:2])
            y ~ dnorm(x[1], 1)
            u[1] ~ dnorm(x[2], 1)
            w = y + u[1]
            u[2] ~ dnorm(w, 1)
        end
        model = compile(model_def, (; x=[1.0, 2.0], eye=[1 0; 0 1]))
        f_ex = generate_expr(model)
        f = eval(f_ex)
        params = rand(3)
        @test Base.invokelatest(f, model.varinfo.values, params) ≈
            LogDensityProblems.logdensity(model, params) rtol = 1e-6
    end

    @testset "example: $ex" for ex in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
        if ex == :lsat # skip for now
            continue
        end
        @info ex
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[ex]
        model = compile(model_def, data, inits)
        expr = JuliaBUGS.generate_expr(model)
        f = eval(expr)
        params = rand(LogDensityProblems.dimension(model))
        @test Base.invokelatest(f, model.varinfo.values, params) ≈
            LogDensityProblems.logdensity(model, params) rtol = 1e-6
    end
end
