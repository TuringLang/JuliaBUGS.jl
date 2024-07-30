@testset "function generation" begin
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
