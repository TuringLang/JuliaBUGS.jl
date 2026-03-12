using Distributed

# Add worker processes, propagating the current project environment
addprocs(2; exeflags=`--project=$(Base.active_project()) --startup-file=no --check-bounds=yes`)

@everywhere begin
    using JuliaBUGS
    using LogDensityProblems
    using Serialization
    using AbstractMCMC
    using AdvancedHMC
    using ADTypes
    using ReverseDiff
    using StableRNGs
end

@testset "Distributed Sampling (Issue #333)" begin
    # Use the same model from issue #333
    data = (
        r=[10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
        n=[39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
        x1=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        x2=[0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
        N=21,
    )

    model_def = @bugs begin
        for i in 1:N
            r[i] ~ dbin(p[i], n[i])
            b[i] ~ dnorm(0.0, tau)
            p[i] = logistic(
                alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
            )
        end
        alpha0 ~ dnorm(0.0, 1.0E-6)
        alpha1 ~ dnorm(0.0, 1.0E-6)
        alpha2 ~ dnorm(0.0, 1.0E-6)
        alpha12 ~ dnorm(0.0, 1.0E-6)
        tau ~ dgamma(0.001, 0.001)
        sigma = 1 / sqrt(tau)
    end

    @testset "BUGSModel serialization to worker (UseGraph mode)" begin
        model = compile(model_def, data)
        D = LogDensityProblems.dimension(model)
        θ = JuliaBUGS.Model.getparams(model)
        local_ld = Base.invokelatest(LogDensityProblems.logdensity, model, θ)

        # Send model to worker and evaluate — this is what MCMCDistributed does
        remote_ld = remotecall_fetch(2, model, θ) do m, p
            Base.invokelatest(LogDensityProblems.logdensity, m, p)
        end

        @test local_ld ≈ remote_ld
    end

    @testset "BUGSModel serialization to worker (UseGeneratedLogDensityFunction mode)" begin
        model = compile(model_def, data)
        model_gen = JuliaBUGS.Model.set_evaluation_mode(
            model, JuliaBUGS.Model.UseGeneratedLogDensityFunction()
        )

        # Verify generated function exists (this is what broke in issue #333)
        @test !isnothing(model_gen.log_density_computation_function)

        D = LogDensityProblems.dimension(model_gen)
        θ = JuliaBUGS.Model.getparams(model_gen)
        local_ld = Base.invokelatest(LogDensityProblems.logdensity, model_gen, θ)

        # This would fail before the fix with:
        #   UndefVarError: `###__compute_log_density__#XXX` not defined in `JuliaBUGS.Model`
        remote_ld = remotecall_fetch(2, model_gen, θ) do m, p
            Base.invokelatest(LogDensityProblems.logdensity, m, p)
        end

        @test local_ld ≈ remote_ld
    end

    @testset "MCMCDistributed sampling" begin
        model = compile(model_def, data)
        ad_model = JuliaBUGS.BUGSModelWithGradient(
            model, AutoReverseDiff(; compile=false)
        )

        D = LogDensityProblems.dimension(model)
        n_samples = 100
        n_adapts = 50
        n_chains = nworkers()

        # This is the exact call pattern from issue #333
        samples = sample(
            StableRNG(1234),
            ad_model,
            NUTS(0.65),
            MCMCDistributed(),
            n_samples,
            n_chains;
            n_adapts=n_adapts,
            init_params=[rand(StableRNG(i), D) for i in 1:n_chains],
            discard_initial=n_adapts,
            progress=false,
        )

        @test length(samples) == n_chains
        @test all(length(chain) == n_samples for chain in samples)
    end
end

rmprocs(workers())
