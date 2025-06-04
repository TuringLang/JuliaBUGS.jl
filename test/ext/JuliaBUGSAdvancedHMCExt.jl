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
            chain_type=Chains,
            n_adapts=n_adapts,
            init_params=initial_θ,
            discard_initial=n_adapts,
        )

        @test samples_and_stats.name_map.parameters ==
            [Symbol("x[3]"), Symbol("x[1:2][1]"), Symbol("x[1:2][2]"), :y]
    end

    @testset "Inference results on examples: $m" for m in [:seeds, :rats, :equiv, :stacks]
        # Retry sampling up to 3 times for numerical stability
        local samples_and_stats
        success = false
        for attempt in 1:3
            try
                data = JuliaBUGS.BUGSExamples.VOLUME_1[m].data
                inits = JuliaBUGS.BUGSExamples.VOLUME_1[m].inits
                model = JuliaBUGS.compile(
                    JuliaBUGS.BUGSExamples.VOLUME_1[m].model_def, data, inits
                )
                ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

                n_samples, n_adapts = 500, 500

                D = LogDensityProblems.dimension(model)
                initial_θ = rand(D)

                samples_and_stats = AbstractMCMC.sample(
                    ad_model,
                    NUTS(0.8),
                    n_samples;
                    chain_type=Chains,
                    n_adapts=n_adapts,
                    init_params=initial_θ,
                    discard_initial=n_adapts,
                )
                success = true
                break
            catch e
                if attempt == 3
                    rethrow(e)
                end
                @warn "Sampling attempt $attempt failed for $m, retrying..." exception = e
                # Reset random seed for different initialization
                Random.seed!(attempt * 42)
            end
        end

        @test success "Failed to obtain samples after 3 attempts for $m"

        ref_inference_results = JuliaBUGS.BUGSExamples.VOLUME_1[m].reference_results
        @testset "$m: $var" for var in keys(ref_inference_results)
            @test summarize(samples_and_stats)[var].nt.mean[1] ≈
                ref_inference_results[var].mean rtol = 0.2
            @test summarize(samples_and_stats)[var].nt.std[1] ≈
                ref_inference_results[var].std rtol = 0.2
        end
    end

    @testset "Inference results on examples: $m" for m in [:birats]
        # Retry sampling up to 3 times for numerical stability
        local samples_and_stats
        success = false
        for attempt in 1:3
            try
                data = JuliaBUGS.BUGSExamples.VOLUME_2[m].data
                inits = JuliaBUGS.BUGSExamples.VOLUME_2[m].inits
                model = JuliaBUGS.compile(
                    JuliaBUGS.BUGSExamples.VOLUME_2[m].model_def, data, inits
                )
                ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

                n_samples, n_adapts = 500, 500
                D = LogDensityProblems.dimension(model)
                initial_θ = rand(D)

                samples_and_stats = AbstractMCMC.sample(
                    ad_model,
                    NUTS(0.6),
                    n_samples;
                    chain_type=Chains,
                    n_adapts=n_adapts,
                    init_params=initial_θ,
                    discard_initial=n_adapts,
                )
                success = true
                break
            catch e
                if attempt == 3
                    rethrow(e)
                end
                @warn "Sampling attempt $attempt failed for $m, retrying..." exception = e
                # Reset random seed for different initialization
                Random.seed!(attempt * 123)
            end
        end

        @test success "Failed to obtain samples after 3 attempts for $m"

        ref_inference_results = JuliaBUGS.BUGSExamples.VOLUME_2[m].reference_results
        @testset "$m: $var" for var in keys(ref_inference_results)
            @test summarize(samples_and_stats)[var].nt.mean[1] ≈
                ref_inference_results[var].mean rtol = 0.2
            @test summarize(samples_and_stats)[var].nt.std[1] ≈
                ref_inference_results[var].std rtol = 0.2
        end
    end
end
