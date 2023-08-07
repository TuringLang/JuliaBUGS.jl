model_def = @bugs begin
    a ~ dbin(0.1, 10)
end

bugs_model = compile(model_def, Dict(), Dict(:a => 10))

@model function dppl_gamma_model()
    return a ~ dbin(0.1, 10)
end

dppl_model = dppl_gamma_model()

vi, bugs_logp = get_vi_logp(bugs_model, false)
params_vi = JuliaBUGS.get_params_varinfo(bugs_model, vi)
# test if JuliaBUGS and DynamicPPL agree on parameters in the model
@test params_in_dppl_model(dppl_model) == keys(params_vi)

vi, dppl_logp = get_vi_logp(dppl_model, vi, false)
@test bugs_logp ≈ dppl_logp rtol = 1E-6

vi, bugs_logp = get_vi_logp(bugs_model, true)
vi, dppl_logp = get_vi_logp(dppl_model, vi, true)
@test bugs_logp ≈ dppl_logp rtol = 1E-6
