model_def = @bugs begin
    a ~ dgamma(0.001, 0.001)
end

bugs_model = compile(model_def, Dict(), Dict(:a => 10))
vi = bugs_model.varinfo

@model function dppl_gamma_model()
    a ~ dgamma(0.001, 0.001)
    return a
end

dppl_model = dppl_gamma_model()

bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, false), DefaultContext())[2]
params_vi = JuliaBUGS.get_params_varinfo(bugs_model, vi)
# test if JuliaBUGS and DynamicPPL agree on parameters in the model
@test params_in_dppl_model(dppl_model) == keys(params_vi)

p = DynamicPPL.LogDensityFunction(dppl_model)
t_p = DynamicPPL.LogDensityFunction(
    dppl_model,
    DynamicPPL.link!!(SimpleVarInfo(dppl_model), dppl_model),
    DynamicPPL.DefaultContext(),
)

@test bugs_logp ≈ LogDensityProblems.logdensity(p, [10.0]) rtol = 1E-6

bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, true), DefaultContext())[2]
@test bugs_logp ≈
    LogDensityProblems.logdensity(t_p, [transform(bijector(dgamma(0.001, 0.001)), 10.0)]) rtol =
    1E-6
