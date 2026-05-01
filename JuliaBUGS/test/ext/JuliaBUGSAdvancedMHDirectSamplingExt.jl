@testset "AdvancedMH direct AbstractMCMC.sample" begin
    model_def = @bugs begin
        α ~ Beta(2, 2)
        β ~ Normal(0, 1)
        for i in 1:N
            y[i] ~ Normal(α + β * x[i], 1)
        end
    end

    N = 20
    x_data = collect(range(-1, 1; length=N))
    y_data = 0.5 .+ 0.3 .* x_data .+ 0.1 .* randn(N)
    model = compile(model_def, (; N=N, x=x_data, y=y_data))

    # Test direct AbstractMCMC.sample with StaticMH
    rng = StableRNG(1234)
    sampler = StaticMH([Normal(0, 0.1)])
    
    chain = Base.invokelatest(
        AbstractMCMC.sample,
        rng,
        model,
        sampler,
        100;
        progress=false,
        chain_type=Chains
    )

    @test chain isa AbstractMCMC.AbstractChains
    @test size(chain, 1) == 100  # 100 samples
    @test size(chain, 2) >= 1  # At least one parameter column

    # Test with RWMH
    rng = StableRNG(1234)
    D = 2  # Dimensionality of the model
    sampler = RWMH(MvNormal(zeros(D), I))
    
    chain = Base.invokelatest(
        AbstractMCMC.sample,
        rng,
        model,
        sampler,
        50;
        progress=false,
        chain_type=Chains
    )

    @test chain isa AbstractMCMC.AbstractChains
    @test size(chain, 1) == 50  # 50 samples
end
