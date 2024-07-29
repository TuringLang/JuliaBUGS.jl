# ReverseDiff

@testset "trans-dim bijectors tape compilation" begin
    # `birats` contains Wishart distribution 
    model_def = JuliaBUGS.BUGSExamples.birats.model_def
    data = JuliaBUGS.BUGSExamples.birats.data
    inits = JuliaBUGS.BUGSExamples.birats.inits
    model = compile(model_def, data, inits)
    ad_model = ADgradient(:ReverseDiff, model; compile=Val(false))
    # random initialization sometimes fails because some parameters are supposed to be from
    # PD matrix
    initial_θ = JuliaBUGS.getparams(model)
    LogDensityProblems.logdensity_and_gradient(ad_model, initial_θ)
end

if VERSION >= v"1.10" && VERSION < v"1.11"
    @testset "Tapir.jl integration" begin
        using Pkg
        Pkg.add("Tapir")
        using ADTypes, Tapir
        for ex in (:rats, :salm, :equiv, :blocker, :leuk)
            (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[ex]
            model = compile(model_def, data, inits)
            ad_model = ADgradient(AutoTapir(), model)
            # testing for no error
            LogDensityProblems.logdensity_and_gradient(
                ad_model, rand(LogDensityProblems.dimension(model))
            )
        end
    end
end

# AdvancedHMC

@testset "AdvancedHMC" begin
    @testset "Generation of parameter names" begin
        model = compile(
            (@bugs begin
                x[1:2] ~ dmnorm(mu[:], sigma[:, :])
                x[3] ~ dnorm(0, 1)
                y = x[1] + x[3]
            end),
            (mu=[0, 0], sigma=[1 0; 0 1]),
            NamedTuple(),
        )

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
        data = JuliaBUGS.BUGSExamples.VOLUME_1[m].data
        inits = JuliaBUGS.BUGSExamples.VOLUME_1[m].inits
        model = JuliaBUGS.compile(JuliaBUGS.BUGSExamples.VOLUME_1[m].model_def, data, inits)

        ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

        n_samples, n_adapts = 2000, 1000

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

        ref_inference_results = JuliaBUGS.BUGSExamples.VOLUME_1[m].reference_results
        @testset "$m: $var" for var in keys(ref_inference_results)
            @test summarize(samples_and_stats)[var].nt.mean[1] ≈
                ref_inference_results[var].mean rtol = 0.2
            @test summarize(samples_and_stats)[var].nt.std[1] ≈
                ref_inference_results[var].std rtol = 0.2
        end
    end

    @testset "Inference results on examples: m" for m in [:birats]
        data = JuliaBUGS.BUGSExamples.VOLUME_2[m].data
        inits = JuliaBUGS.BUGSExamples.VOLUME_2[m].inits
        model = JuliaBUGS.compile(JuliaBUGS.BUGSExamples.VOLUME_2[m].model_def, data, inits)

        ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

        n_samples, n_adapts = 3000, 1000

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

        ref_inference_results = JuliaBUGS.BUGSExamples.VOLUME_2[m].reference_results
        @testset "$m: $var" for var in keys(ref_inference_results)
            @test summarize(samples_and_stats)[var].nt.mean[1] ≈
                ref_inference_results[var].mean rtol = 0.2
            @test summarize(samples_and_stats)[var].nt.std[1] ≈
                ref_inference_results[var].std rtol = 0.2
        end
    end
end
