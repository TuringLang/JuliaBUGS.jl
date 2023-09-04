dist = LKJ(10, 0.5)
test_θ_transformed = rand(45)
test_θ = DynamicPPL.invlink_and_reconstruct(dist, test_θ_transformed)

test_lkj = @bugs begin
    x[1:10, 1:10] ~ LKJ(10, 0.5)
end

bugs_model = compile(test_lkj, Dict(), Dict(:x => test_θ))
vi = bugs_model.varinfo

# test param length given trans-dim bijectors
@test JuliaBUGS.get_param_length(JuliaBUGS.settrans!!(test_lkj_model, false)) == 100
@test JuliaBUGS.get_param_length(JuliaBUGS.settrans!!(test_lkj_model, true)) == 45

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

bugs_logp =
    JuliaBUGS.evaluate!!(
        DynamicPPL.settrans!!(bugs_model, false), DefaultBUGSContext()
    ).logp
dppl_logp = LogDensityProblems.logdensity(p, vcat(test_θ...))
@test bugs_logp ≈ dppl_logp rtol = 1E-6

bugs_logp =
    JuliaBUGS.evaluate!!(DynamicPPL.settrans!!(bugs_model, true), DefaultBUGSContext()).logp
bugs_logp_logp_ctx =
    evaluate!!(settrans!!(bugs_model, true), LogDensityContext(), test_θ_transformed).logp
@test bugs_logp == bugs_logp_logp_ctx
dppl_logp = LogDensityProblems.logdensity(t_p, test_θ_transformed)
@test bugs_logp ≈ dppl_logp rtol = 1E-6
