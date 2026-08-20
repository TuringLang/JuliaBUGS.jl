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
    ad_model = compile(
        model_def, (mu=[0, 0], B=[1 0; 0 1]), (A=[1 0; 0 1],); adtype=AutoReverseDiff()
    )

    theta = [
        0.7931743744870574,
        0.5151017206811268,
        0.8572080685579707,
        0.10876988860066528,
        0.4693124986437822,
    ]
    LogDensityProblems.logdensity_and_gradient(ad_model, theta)
end

@testset "dweib matches the BUGS parameterization" begin
    # BUGS: p(x | a, b) = a * b * x^(a-1) * exp(-b * x^a)
    bugs_weibull_pdf(x, a, b) = a * b * x^(a - 1) * exp(-b * x^a)
    for (a, b) in ((0.5, 2.0), (1.0, 3.0), (2.0, 3.0), (3.5, 0.2)), x in (0.1, 0.7, 2.5)
        @test pdf(JuliaBUGS.dweib(a, b), x) ≈ bugs_weibull_pdf(x, a, b)
    end
    # a = 1 is the exponential distribution with rate b
    @test pdf(JuliaBUGS.dweib(1.0, 3.0), 0.7) ≈ pdf(Exponential(1 / 3.0), 0.7)
end

@testset "dt with non-standard location/scale can be sampled" begin
    using StableRNGs: StableRNG
    using Statistics: median, quantile
    d = JuliaBUGS.dt(1.0, 4.0, 3.0) # μ = 1, τ = 4 (σ = 1/2), ν = 3
    @test d isa JuliaBUGS.BUGSPrimitives.TDistShiftedScaled
    @test minimum(d) == -Inf && maximum(d) == Inf
    rng = StableRNG(1)
    xs = rand(rng, d, 200_000)
    @test mean(xs) ≈ 1.0 atol = 0.02  # mean of a t with ν = 3 exists and equals μ
    @test median(xs) ≈ 1.0 atol = 0.02
    # standardizing recovers a standard t: compare an interquartile range
    @test quantile((xs .- 1.0) ./ 0.5, 0.75) ≈ quantile(TDist(3.0), 0.75) atol = 0.03

    # compiling a model with such a prior no longer needs initial values
    model_def = @bugs begin
        x ~ dt(1, 4, 3)
    end
    model = compile(model_def, NamedTuple())
    @test model isa JuliaBUGS.BUGSModel
    @test model.transformed_param_length == 1
    @test isfinite(LogDensityProblems.logdensity(model, [0.3]))
end
