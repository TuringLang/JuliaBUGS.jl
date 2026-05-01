@testset "AdvancedSliceSampling direct AbstractMCMC.sample" begin
    model_def = @bugs begin
        μ ~ Normal(0, 10)
        σ ~ HalfNormal(1)
        for i in 1:N
            y[i] ~ Normal(μ, σ)
        end
    end

    N = 20
    y_data = randn(N) .+ 2.0
    model = compile(model_def, (; N=N, y=y_data))

    # Test direct AbstractMCMC.sample with SliceSampling
    rng = StableRNG(1234)
    sampler = Slice()  # Default slice sampler
    
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
    @test size(chain, 2) >= 2  # At least two parameters (μ and σ)

    # Check that samples are in reasonable range
    μ_samples = vec(chain[:μ].data)
    σ_samples = vec(chain[:σ].data)
    @test all(isfinite, μ_samples)
    @test all(isfinite, σ_samples)
    @test all(σ_samples .> 0)  # σ should be positive
end
