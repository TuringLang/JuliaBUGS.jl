# ReverseDiff

@testset "trans-dim bijectors tape compilation" begin
    # `birats` contains Dirichlet distribution 
    model_def = JuliaBUGS.BUGSExamples.birats.model_def
    data = JuliaBUGS.BUGSExamples.birats.data
    inits = JuliaBUGS.BUGSExamples.birats.inits[1]
    model = compile(model_def, data, inits)
    ad_model = ADgradient(:ReverseDiff, model; compile=Val(false))
    D = LogDensityProblems.dimension(model)
    initial_θ = rand(D)
    LogDensityProblems.logdensity_and_gradient(ad_model, initial_θ)
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

    reference_results = (
        seeds=(
            alpha0=(mean=-0.5499, std=0.1965),
            alpha1=(mean=0.08902, std=0.3124),
            alpha12=(mean=-0.841, std=0.4372),
            alpha2=(mean=1.356, std=0.2772),
            sigma=(mean=0.2922, std=0.1467),
        ),
        rats=(
            alpha0=(mean=106.6, std=3.66),
            var"beta.c"=(mean=6.186, std=0.1086),
            sigma=(mean=6.093, std=0.4643),
        ),
        equiv=(
            equiv=(mean=0.998, std=0.04468),
            mu=(mean=1.436, std=0.05751),
            phi=(mean=-0.008613, std=0.05187),
            sigma1=(mean=0.1102, std=0.03268),
        ),
        stacks=(b0=(mean=-39.64, std=12.63), var"outlier[21]"=(mean=0.3324, std=0.4711)),
    )
    @testset "Inference results on examples: $m" for m in [:seeds, :rats, :equiv, :stacks]
        data = JuliaBUGS.BUGSExamples.VOLUME_I[m].data
        inits = JuliaBUGS.BUGSExamples.VOLUME_I[m].inits[1]
        model = JuliaBUGS.compile(JuliaBUGS.BUGSExamples.VOLUME_I[m].model_def, data, inits)

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

        @testset "$m: $var" for var in keys(reference_results[m])
            begin
                @test summarize(samples_and_stats)[var].nt.mean[1] ≈
                    reference_results[m][var].mean rtol = 0.1
                @test summarize(samples_and_stats)[var].nt.std[1] ≈
                    reference_results[m][var].std rtol = 0.1
            end
        end
    end
end
