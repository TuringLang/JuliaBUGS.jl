@testset "`inv` with `Bijectors.cholesky_lower`" begin
    A = [
        1.0 -0.421554 0.15512
        -0.421554 1.0 0.447138
        0.15512 0.447138 1.0
    ]
    A_tracked = ReverseDiff.track(A)
    @test_throws PosDefException inv(Distributions.PDMat(A_tracked))
    @test map(x -> x.value, JuliaBUGS.BUGSPrimitives._inv(Distributions.PDMat(A_tracked))) ≈
        inv(A) rtol = 1e-6
end

@testset "Example model with dwish and dmnorm" begin
    model_def = @bugs begin
        A[1:2, 1:2] ~ dwish(B[:, :], 2)
        C[1:2] ~ dmnorm(mu[:], A[:, :])
    end
    model = compile(model_def, (mu=[0, 0], B=[1 0; 0 1]), (A=[1 0; 0 1],))

    ad_model = ADgradient(:ReverseDiff, model)
    theta = [
        0.7931743744870574,
        0.5151017206811268,
        0.8572080685579707,
        0.10876988860066528,
        0.4693124986437822,
    ]
    LogDensityProblems.logdensity_and_gradient(ad_model, theta)
end

@testset "inprod(a,b)" begin
    A = [3, 0.7, 6]
    B = [2.6, 1.3, 3]
    @test JuliaBUGS.BUGSPrimitives.inprod(A, B) == 26.71
end
