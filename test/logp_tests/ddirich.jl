alpha = rand(10)
dist = ddirich(alpha)
test_θ_transformed = rand(9)
test_θ = DynamicPPL.invlink_and_reconstruct(dist, test_θ_transformed)

rand(dist)
# Define the BUGS model
test_ddirich = @bugs begin
    x[1:10] ~ ddirich(alpha[1:10])
end

# Compile the BUGS model
bugs_model = compile(test_ddirich, Dict(:alpha => alpha), Dict(:x => test_θ))

# Now, create a DynamicPPL model to represent the same distribution
@model function ddirich_test()
    x ~ ddirich(alpha[1:10])
    return x
end

dppl_model = ddirich_test()

# Follow the rest of the structure of your script to test the log-density and other properties,
# similar to what you did for the LKJ distribution but adjusting for the Wishart distribution.

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
