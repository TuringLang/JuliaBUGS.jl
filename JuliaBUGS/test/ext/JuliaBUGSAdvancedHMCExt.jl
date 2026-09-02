@testset "AdvancedHMC" begin
    @testset "sample prepares AD models in function scope" begin
        @model function normal_location_hmc((; y, mu), sigma, N)
            mu ~ Normal(0, 10)
            for i in 1:N
                y[i] ~ Normal(mu, sigma)
            end
        end

        function run_sampling(args...)
            model = normal_location_hmc((; y=[1.2, 0.9, 1.4]), 1.0, 3)
            callback_models = Any[]
            function callback(
                rng, sampled_model, sampler, transition, state, iteration; kwargs...
            )
                return push!(callback_models, sampled_model.logdensity)
            end
            draws = AbstractMCMC.sample(
                StableRNG(1234),
                model,
                HMC(0.1, 2),
                args...;
                adtype=AutoReverseDiff(; compile=false),
                callback,
                n_adapts=0,
                progress=false,
            )
            return draws, callback_models
        end

        draws, callback_models = run_sampling(3)
        is_ad_model =
            m -> m isa JuliaBUGS.BUGSModelWithGradient && m.adtype isa AutoReverseDiff

        @test length(draws) == length(callback_models) == 3
        @test all(is_ad_model, callback_models)

        chains, callback_models = run_sampling(MCMCSerial(), 2, 2)
        @test length(chains) == 2
        @test all(chain -> length(chain) == 2, chains)
        @test length(callback_models) == 4
        @test all(is_ad_model, callback_models)
    end

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
        samples_and_stats = Base.invokelatest(
            AbstractMCMC.sample,
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
        initial_θ = Base.invokelatest(JuliaBUGS.getparams, ad_model.base_model)

        samples_and_stats = Base.invokelatest(
            AbstractMCMC.sample,
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
