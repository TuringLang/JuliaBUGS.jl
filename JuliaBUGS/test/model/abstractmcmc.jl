using JuliaBUGS
using JuliaBUGS: IndependentMH
using AbstractMCMC
using Random
using Test

@testset "AbstractMCMC Callbacks" begin
    model_def = @bugs begin
        mu ~ dnorm(0, 0.01)
        tau ~ dgamma(0.01, 0.01)
        for i in 1:N
            y[i] ~ dnorm(mu, tau)
        end
    end

    data = (N=5, y=[1.2, 0.8, 1.5, 1.1, 0.9])
    model = compile(model_def, data)
    logdensitymodel = AbstractMCMC.LogDensityModel(model)

    rng = Random.MersenneTwister(42)
    sampler = IndependentMH()
    transition, state = AbstractMCMC.step(rng, logdensitymodel, sampler)

    @testset "ParamsWithStats with params only" begin
        pws = AbstractMCMC.ParamsWithStats(
            logdensitymodel, sampler, transition, state; params=true, stats=false
        )
        @test haskey(pws.params, :mu)
        @test haskey(pws.params, :tau)
        @test pws.stats == NamedTuple()
    end

    @testset "ParamsWithStats with stats" begin
        pws = AbstractMCMC.ParamsWithStats(
            logdensitymodel, sampler, transition, state; params=true, stats=true
        )
        @test haskey(pws.params, :mu)
        @test haskey(pws.stats, :lp)
        @test pws.stats.lp isa Real
    end

    @testset "ParamsWithStats with no params" begin
        pws = AbstractMCMC.ParamsWithStats(
            logdensitymodel, sampler, transition, state; params=false, stats=true
        )
        @test pws.params == NamedTuple()
        @test haskey(pws.stats, :lp)
    end

    @testset "Callback integration with sample" begin
        collected = []
        function callback(rng, model, sampler, transition, state, iteration; kwargs...)
            pws = AbstractMCMC.ParamsWithStats(
                model, sampler, transition, state; params=true, stats=true
            )
            push!(collected, (iter=iteration, params=pws.params, lp=pws.stats.lp))
        end

        chain = sample(rng, model, sampler, 3; callback=callback, progress=false)

        @test length(collected) == 3
        @test all(c -> haskey(c.params, :mu), collected)
        @test all(c -> haskey(c.params, :tau), collected)
        @test all(c -> c.lp isa Real, collected)
    end

    @testset "mcmc_callback wrapper" begin
        collected = []

        # mcmc_callback wraps raw callbacks - it doesn't take params/stats kwargs
        # Those are for the TensorBoard extension
        cb = AbstractMCMC.mcmc_callback() do rng,
        model, sampler, transition, state,
        iteration
            pws = AbstractMCMC.ParamsWithStats(
                model, sampler, transition, state; params=true, stats=true
            )
            push!(collected, (iter=iteration, mu=pws.params.mu))
        end

        chain = sample(rng, model, sampler, 3; callback=cb, progress=false)

        @test length(collected) == 3
        @test all(c -> haskey(c, :mu), collected)
    end
end
