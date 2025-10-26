@testset "AdvancedHMC" begin
    @testset "Generation of parameter names" begin
        model_def = @bugs begin
            x[1:2] ~ dmnorm(mu[:], sigma[:, :])
            x[3] ~ dnorm(0, 1)
            y = x[1] + x[3]
        end
        data = (mu=[0, 0], sigma=[1 0; 0 1])
        ad_model = compile(model_def, data; adtype=AutoReverseDiff(; compile=true))
        n_samples, n_adapts = 10, 0
        D = LogDensityProblems.dimension(ad_model)
        initial_θ = rand(D)
        samples_and_stats = AbstractMCMC.sample(
            StableRNG(1234),
            ad_model,
            NUTS(0.8),
            n_samples;
            progress=false,
            chain_type=Chains,
            n_adapts=n_adapts,
            init_params=initial_θ,
            discard_initial=n_adapts,
        )

        @test samples_and_stats.name_map.parameters ==
            [Symbol("x[3]"), Symbol("x[1:2][1]"), Symbol("x[1:2][2]"), :y]
    end

    @testset "AD backend sampling" begin
        model_def = @bugs begin
            mu ~ dnorm(0, 1)
            for i in 1:N
                y[i] ~ dnorm(mu, 1)
            end
        end
        data = (N=5, y=[1.0, 2.0, 1.5, 2.5, 1.8])

        # Test that ReverseDiff backend works
        ad_model_compiled = compile(model_def, data; adtype=AutoReverseDiff(; compile=true))
        ad_model_nocompile = compile(
            model_def, data; adtype=AutoReverseDiff(; compile=false)
        )

        @test ad_model_compiled isa JuliaBUGS.Model.BUGSModelWithGradient
        @test ad_model_nocompile isa JuliaBUGS.Model.BUGSModelWithGradient

        # Test that both produce equivalent results
        n_samples, n_adapts = 100, 100
        D = LogDensityProblems.dimension(ad_model_compiled)
        initial_θ = rand(StableRNG(123), D)

        samples_compiled = AbstractMCMC.sample(
            StableRNG(1234),
            ad_model_compiled,
            NUTS(0.8),
            n_samples;
            progress=false,
            chain_type=Chains,
            n_adapts=n_adapts,
            init_params=initial_θ,
            discard_initial=n_adapts,
        )

        samples_nocompile = AbstractMCMC.sample(
            StableRNG(1234),
            ad_model_nocompile,
            NUTS(0.8),
            n_samples;
            progress=false,
            chain_type=Chains,
            n_adapts=n_adapts,
            init_params=initial_θ,
            discard_initial=n_adapts,
        )

        # Results should be very similar (same RNG seed)
        @test summarize(samples_compiled)[:mu].nt.mean[1] ≈
            summarize(samples_nocompile)[:mu].nt.mean[1] rtol = 0.1
    end

    @testset "Inference results on examples: $example" for example in
                                                           [:seeds, :rats, :stacks]
        (; model_def, data, inits, reference_results) = Base.getfield(
            JuliaBUGS.BUGSExamples, example
        )
        ad_model = JuliaBUGS.compile(
            model_def, data, inits; adtype=AutoReverseDiff(; compile=true)
        )

        n_samples, n_adapts = 1000, 1000

        D = LogDensityProblems.dimension(ad_model)
        initial_θ = JuliaBUGS.getparams(ad_model.base_model)

        samples_and_stats = AbstractMCMC.sample(
            StableRNG(1234),
            ad_model,
            NUTS(0.8),
            n_samples;
            progress=false,
            chain_type=Chains,
            n_adapts=n_adapts,
            init_params=initial_θ,
            discard_initial=n_adapts,
        )

        @testset "$example: $var" for var in keys(reference_results)
            @test summarize(samples_and_stats)[var].nt.mean[1] ≈ reference_results[var].mean rtol =
                0.3
            @test summarize(samples_and_stats)[var].nt.std[1] ≈ reference_results[var].std rtol =
                0.3
        end
    end
end
