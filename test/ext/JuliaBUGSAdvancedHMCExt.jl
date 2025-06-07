@testset "AdvancedHMC" begin
    @testset "Generation of parameter names" begin
        model_def = @bugs begin
            x[1:2] ~ dmnorm(mu[:], sigma[:, :])
            x[3] ~ dnorm(0, 1)
            y = x[1] + x[3]
        end
        data = (mu=[0, 0], sigma=[1 0; 0 1])
        model = compile(model_def, data)
        ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))
        n_samples, n_adapts = 10, 0
        D = LogDensityProblems.dimension(model)
        initial_θ = rand(D)
        samples_and_stats = AbstractMCMC.sample(
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

    @testset "Inference results on examples: $example" for example in
                                                           [:seeds, :rats, :stacks]
        (; model_def, data, inits, reference_results) = Base.getfield(
            JuliaBUGS.BUGSExamples, example
        )
        model = JuliaBUGS.compile(model_def, data, inits)
        ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

        n_samples, n_adapts = 1000, 1000

        D = LogDensityProblems.dimension(model)
        initial_θ = JuliaBUGS.getparams(model)

        samples_and_stats = AbstractMCMC.sample(
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
