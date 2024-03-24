dist = LKJ(10, 0.5)
test_θ_transformed = rand(45)
test_θ = DynamicPPL.invlink_and_reconstruct(dist, test_θ_transformed)

test_lkj = @bugs begin
    x[1:10, 1:10] ~ LKJ(10, 0.5)
end

bugs_model = compile(test_lkj, Dict(), Dict(:x => test_θ))
vi = bugs_model.varinfo

# test param length given trans-dim bijectors
@test LogDensityProblems.dimension(JuliaBUGS.settrans(bugs_model, false)) == 100
@test LogDensityProblems.dimension(JuliaBUGS.settrans(bugs_model, true)) == 45

@model function lkj_test()
    x = Matrix{Float64}(undef, 10, 10)
    x ~ LKJ(10, 0.5)
    return x
end

dppl_model = lkj_test()

p = DynamicPPL.LogDensityFunction(dppl_model)
t_p = DynamicPPL.LogDensityFunction(
    dppl_model,
    DynamicPPL.link!!(SimpleVarInfo(dppl_model), dppl_model),
    DynamicPPL.DefaultContext(),
)

bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, false), DefaultContext())[2]
dppl_logp = LogDensityProblems.logdensity(p, vcat(test_θ...))
@test bugs_logp ≈ dppl_logp rtol = 1E-6

bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, true), DefaultContext())[2]
bugs_logp_logp_ctx = evaluate!!(
    JuliaBUGS.settrans(bugs_model, true), LogDensityContext(), test_θ_transformed
)[2]
@test bugs_logp == bugs_logp_logp_ctx
@test bugs_logp == LogDensityProblems.logdensity(
    JuliaBUGS.settrans(bugs_model, true), test_θ_transformed
)
dppl_logp = LogDensityProblems.logdensity(t_p, test_θ_transformed)
@test bugs_logp ≈ dppl_logp rtol = 1E-6
