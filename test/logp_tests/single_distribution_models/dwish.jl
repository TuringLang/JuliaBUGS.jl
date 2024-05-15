# Define a scale matrix and degrees of freedom
scale_matrix = randn(10, 10)
scale_matrix = scale_matrix * transpose(scale_matrix)  # Ensuring positive-definiteness
degrees_of_freedom = 12

dist = dwish(scale_matrix, degrees_of_freedom)
test_θ_transformed = rand(55)
test_θ = DynamicPPL.invlink_and_reconstruct(dist, test_θ_transformed)

# Define the BUGS model
test_dwish = @bugs begin
    x[1:10, 1:10] ~ dwish(scale_matrix[:, :], degrees_of_freedom)
end

# Compile the BUGS model
bugs_model = compile(
    test_dwish,
    (degrees_of_freedom=degrees_of_freedom, scale_matrix=scale_matrix),
    (x=test_θ,),
)

# Now, create a DynamicPPL model to represent the same distribution
@model function dwish_test()
    x ~ dwish(scale_matrix, degrees_of_freedom)
    return x
end

dppl_model = dwish_test()

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
@test bugs_logp ≈ bugs_logp_logp_ctx rtol = 1E-6
@test bugs_logp ≈ LogDensityProblems.logdensity(
    JuliaBUGS.settrans(bugs_model, true), test_θ_transformed
) rtol = 1E-6
dppl_logp = LogDensityProblems.logdensity(t_p, test_θ_transformed)
@test bugs_logp ≈ dppl_logp rtol = 1E-6
