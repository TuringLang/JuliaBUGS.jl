# Tests for `getparams`, using `Rats` model
@testset "`getparams` with Rats" begin
    m = :rats
    data = JuliaBUGS.BUGSExamples.VOLUME_I[m].data
    inits = JuliaBUGS.BUGSExamples.VOLUME_I[m].inits[1]
    model = JuliaBUGS.compile(JuliaBUGS.BUGSExamples.VOLUME_I[m].model_def, data, inits)
    model_notran = JuliaBUGS.settrans(model, false)

    @test LogDensityProblems.logdensity(model, JuliaBUGS.getparams(model)) ==
        JuliaBUGS.evaluate!!(model)[2]
    @test LogDensityProblems.logdensity(model_notran, JuliaBUGS.getparams(model_notran)) ==
        JuliaBUGS.evaluate!!(model_notran)[2]
end
