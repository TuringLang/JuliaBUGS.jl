model_def = @bugs begin
    a ~ dgamma(0.001, 0.001)
end

bugs_model = compile(model_def, Dict(), Dict(:a => 10))

@model function dppl_gamma_model()
    a ~ dgamma(0.001, 0.001)
    return a
end

dppl_model = dppl_gamma_model()

vi, bugs_logp = get_vi_logp(bugs_model, false)
params_vi = JuliaBUGS.get_params_varinfo(bugs_model, vi)
# test if JuliaBUGS and DynamicPPL agree on parameters in the model
@test params_in_dppl_model(dppl_model) == keys(params_vi)

p = DynamicPPL.LogDensityFunction(dppl_model)
t_p = DynamicPPL.LogDensityFunction(dppl_model, DynamicPPL.link!!(SimpleVarInfo(dppl_model), dppl_model), DynamicPPL.DefaultContext())

_, dppl_logp = get_vi_logp(dppl_model, vi, false)
@test LogDensityProblems.logdensity(p, [10.0]) ≈ dppl_logp rtol = 1E-6
@test bugs_logp ≈ dppl_logp rtol = 1E-6

_, bugs_logp = get_vi_logp(bugs_model, true)
vi = prepare_transformed_varinfo(bugs_model)
_, dppl_logp = get_vi_logp(dppl_model, vi, true)
@test LogDensityProblems.logdensity(t_p, [transform(bijector(dgamma(0.001, 0.001)), 10.0)]) ≈ dppl_logp rtol = 1E-6
@test bugs_logp ≈ dppl_logp rtol = 1E-6
