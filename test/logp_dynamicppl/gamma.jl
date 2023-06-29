model_def = @bugsast begin
    a ~ dgamma(0.001, 0.001)
end

bugs_model = compile(model_def, Dict(), Dict(:a => 10))

@model function dppl_gamma_model()
    return a ~ dgamma(0.001, 0.001)
end

dppl_model = dppl_gamma_model()

for t in [true, false]
    compare_dppl_bugs_logps(dppl_model, bugs_model, t)
end
