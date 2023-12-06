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
