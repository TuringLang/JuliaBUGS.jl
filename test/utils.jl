@testset "Decompose for loop" begin
    ex = MacroTools.@q for i in 1:3
        x[i] = i
        for j in 1:3
            y[i, j] = i + j
        end
    end

    loop_var, lb, ub, body = JuliaBUGS.decompose_for_expr(ex)
    
    @test loop_var == :i
    @test lb == 1
    @test ub == 3
    @test body == MacroTools.@q begin
        x[i] = i
        for j in 1:3
            y[i, j] = i + j
        end
    end
end

# Tests for `getparams`, using `Rats` model
@testset "`getparams` with Rats" begin
    m = :rats
    data = JuliaBUGS.BUGSExamples.VOLUME_I[m].data
    inits = JuliaBUGS.BUGSExamples.VOLUME_I[m].inits[1]
    model = JuliaBUGS.compile(JuliaBUGS.BUGSExamples.VOLUME_I[m].model_def, data, inits)

    # transformed
    @test LogDensityProblems.logdensity(
        model, JuliaBUGS.getparams(model; transformed=true)
    ) == evaluate!!(model, JuliaBUGS.DefaultContext())[2]
    # untransformed
    @test LogDensityProblems.logdensity(
        JuliaBUGS.settrans(model), JuliaBUGS.getparams(model; transformed=false)
    ) == evaluate!!(JuliaBUGS.settrans(model), JuliaBUGS.DefaultContext())[2]
end
