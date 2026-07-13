using JuliaBUGS
using JuliaBUGS: IndependentMH
using AbstractMCMC
using Random
using Test

# Used by the "chain_type=Any passes unintegrated sampler transitions through" testset;
# type definitions are not allowed inside a @testset's local scope.
struct _UnintegratedTransition
    x::Float64
end
struct _UnintegratedSampler <: AbstractMCMC.AbstractSampler end

@testset "AbstractMCMC Callbacks" begin
    callback_model_def = @bugs begin
        mu ~ dnorm(0, 0.01)
        tau ~ dgamma(0.01, 0.01)
        for i in 1:N
            y[i] ~ dnorm(mu, tau)
        end
    end

    data = (N=5, y=[1.2, 0.8, 1.5, 1.1, 0.9])
    model = compile(callback_model_def, data)
    logdensitymodel = AbstractMCMC.LogDensityModel(model)

    rng = Random.MersenneTwister(42)
    sampler = IndependentMH()
    transition, state = AbstractMCMC.step(rng, logdensitymodel, sampler)

    @testset "ParamsWithStats with params only" begin
        pws = AbstractMCMC.ParamsWithStats(
            logdensitymodel, sampler, transition, state; params=true, stats=false
        )
        @test pws.params isa AbstractPPL.VarNamedTuple
        @test haskey(pws.params, @varname(mu))
        @test haskey(pws.params, @varname(tau))
        @test pws.stats == NamedTuple()
    end

    @testset "ParamsWithStats with stats" begin
        pws = AbstractMCMC.ParamsWithStats(
            logdensitymodel, sampler, transition, state; params=true, stats=true
        )
        @test haskey(pws.params, @varname(mu))
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
        @test all(c -> haskey(c.params, @varname(mu)), collected)
        @test all(c -> haskey(c.params, @varname(tau)), collected)
        @test all(c -> c.lp isa Real, collected)
    end

    @testset "mcmc_callback wrapper" begin
        collected = []

        cb = AbstractMCMC.mcmc_callback() do rng,
        model, sampler, transition, state,
        iteration
            pws = AbstractMCMC.ParamsWithStats(
                model, sampler, transition, state; params=true, stats=true
            )
            push!(collected, (iter=iteration, mu=pws.params[@varname(mu)]))
        end

        chain = sample(rng, model, sampler, 3; callback=cb, progress=false)

        @test length(collected) == 3
        @test all(c -> haskey(c, :mu), collected)
    end

    @testset "ParamsWithStats with auto-marginalization reports flat parameters" begin
        model_def = @bugs begin
            mu ~ Normal(0, 1)
            z ~ Categorical(w[1:K])
            y ~ Normal(mu + delta[z], sigma)
        end

        model = compile(model_def, (K=2, w=[0.3, 0.7], delta=[0.0, 2.0], sigma=1.0, y=1.5))
        model = JuliaBUGS.settrans(model, true)
        model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseAutoMarginalization())
        transition, log_densities = JuliaBUGS.Model.evaluate_with_marginalization_values!!(
            model, [0.0]
        )

        pws = AbstractMCMC.ParamsWithStats(
            AbstractMCMC.LogDensityModel(model),
            sampler,
            transition,
            state;
            params=true,
            stats=true,
        )

        @test haskey(pws.params, @varname(mu))
        @test !haskey(pws.params, @varname(z))
        @test pws.stats.lp ≈ log_densities.tempered_logjoint
    end

    @testset "chain_type=Any returns canonical structured samples" begin
        raw_model = compile(callback_model_def, data)
        samples = sample(
            MersenneTwister(123), raw_model, sampler, 4; chain_type=Any, progress=false
        )

        @test length(samples) == 4
        @test all(sample -> sample isa AbstractMCMC.ParamsWithStats, samples)
        @test all(sample -> sample.params isa AbstractPPL.VarNamedTuple, samples)
        @test all(sample -> haskey(sample.params, @varname(mu)), samples)
        @test all(sample -> haskey(sample.params, @varname(tau)), samples)
        @test all(sample -> isempty(sample.extras), samples)
    end

    @testset "chain_type=Any passes unintegrated sampler transitions through" begin
        # A sampler without a `_transition_params_and_stats` integration must keep
        # AbstractMCMC's default behavior of returning native transitions unchanged,
        # not error at bundle time.
        transitions = [_UnintegratedTransition(1.0), _UnintegratedTransition(2.0)]
        bundled = AbstractMCMC.bundle_samples(
            transitions, logdensitymodel, _UnintegratedSampler(), nothing, Any
        )
        @test bundled === transitions
    end
end
