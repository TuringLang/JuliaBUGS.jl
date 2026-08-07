using JuliaBUGS: Gibbs, IndependentMH
using JuliaBUGS.Model: ParamsDict, set_evaluation_mode, settrans, UseAutoMarginalization

const PWSVector = Vector{AbstractMCMC.ParamsWithStats}

@testset "ParamsWithStats output" begin
    model_def = @bugs begin
        alpha ~ dnorm(0, 0.01)
        for i in 1:N
            y[i] ~ dnorm(alpha, 1)
        end
        doubled = 2 * alpha
    end
    data = (N=3, y=[1.2, 0.8, 1.5])
    model = compile(model_def, data, (; alpha=0.0))

    @testset "IndependentMH reports parameters and generated quantities" begin
        draws = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(1234),
            model,
            IndependentMH(),
            20;
            progress=false,
            chain_type=PWSVector,
        )

        @test draws isa Vector{<:AbstractMCMC.ParamsWithStats}
        @test length(draws) == 20
        @test all(d -> d.params isa ParamsDict, draws)
        @test Set(keys(draws[1].params)) == Set([@varname(alpha), @varname(doubled)])
        @test draws[1].params[@varname(alpha)] isa Real
        @test draws[1].params[@varname(doubled)] ≈ 2 * draws[1].params[@varname(alpha)]
        # The sampler reports no statistics of its own, so the model's log density stands in.
        @test keys(draws[1].stats) == (:lp,)
        @test all(d -> isfinite(d.stats.lp), draws)
    end

    @testset "Base.pairs flattens parameters and statistics" begin
        draws = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(2468),
            model,
            IndependentMH(),
            5;
            progress=false,
            chain_type=PWSVector,
        )

        names = [first(p) for p in Base.pairs(draws[1])]
        @test Set(names) == Set([@varname(alpha), @varname(doubled), :lp])
    end

    @testset "Gibbs reports parameters" begin
        sampler_map = OrderedDict(@varname(alpha) => IndependentMH())
        draws = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(1357),
            model,
            Gibbs(model, sampler_map),
            10;
            progress=false,
            chain_type=PWSVector,
        )

        @test length(draws) == 10
        @test haskey(draws[1].params, @varname(alpha))
        @test keys(draws[1].stats) == (:lp,)
    end

    @testset "HMC records sampler statistics" begin
        ad_model = compile(model_def, data, (; alpha=0.0); adtype=AutoReverseDiff())
        draws = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(2244),
            ad_model,
            NUTS(0.8),
            30;
            progress=false,
            chain_type=PWSVector,
            n_adapts=20,
            discard_initial=20,
        )

        @test length(draws) == 30
        @test haskey(draws[1].params, @varname(alpha))
        @test haskey(draws[1].stats, :lp)
        @test haskey(draws[1].stats, :acceptance_rate)
        @test all(d -> isfinite(d.stats.lp), draws)
    end

    @testset "multivariate variables are stored whole" begin
        multivariate_def = @bugs begin
            x[1:2] ~ dmnorm(mu[1:2], tau[1:2, 1:2])
            z ~ dnorm(x[1] + x[2], 1)
        end
        multivariate_model = compile(
            multivariate_def, (mu=[0.0, 0.0], tau=[1.0 0.0; 0.0 1.0], z=0.5)
        )

        draws = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(4321),
            multivariate_model,
            IndependentMH(),
            10;
            progress=false,
            chain_type=PWSVector,
        )

        @test size(draws[1].params[@varname(x[1:2])]) == (2,)
        # Each draw owns its arrays; the evaluation environment's buffers are reused.
        xs = [d.params[@varname(x[1:2])] for d in draws]
        @test length(unique(objectid.(xs))) == length(xs)
    end

    @testset "auto-marginalization recovers the marginalized latent" begin
        marginalized_def = @bugs begin
            mu ~ Normal(0, 1)
            z ~ Categorical(w[1:2])
            y ~ Normal(mu + z, 1)
        end
        marginalized_model = compile(marginalized_def, (; w=[0.5, 0.5], y=1.0))
        marginalized_model = set_evaluation_mode(
            settrans(marginalized_model, true), UseAutoMarginalization()
        )

        samples = [[m] for m in range(-1.0, 1.0; length=10)]
        draws = JuliaBUGS.gen_chains(
            PWSVector,
            marginalized_model,
            samples,
            fill(NamedTuple(), length(samples));
            rng=StableRNG(2024),
        )

        @test [d.params[@varname(mu)] for d in draws] ≈ [s[1] for s in samples]
        @test all(d -> d.params[@varname(z)] in (1, 2), draws)
    end
end

@testset "generated-quantity reconstruction is reproducible" begin
    gq_def = @bugs begin
        mu ~ dnorm(0, 1)
        y ~ dnorm(mu, 1)
        pred ~ dnorm(mu, 1)
    end
    gq_model = compile(gq_def, (; y=0.7), (; mu=0.0))

    run() = Base.invokelatest(
        AbstractMCMC.sample,
        StableRNG(7),
        gq_model,
        IndependentMH(),
        20;
        progress=false,
        chain_type=PWSVector,
    )
    a, b = run(), run()
    @test [d.params[@varname(pred)] for d in a] == [d.params[@varname(pred)] for d in b]

    multi() = Base.invokelatest(
        AbstractMCMC.sample,
        StableRNG(7),
        gq_model,
        IndependentMH(),
        MCMCSerial(),
        20,
        3;
        progress=false,
        chain_type=PWSVector,
    )
    ma, mb = multi(), multi()
    preds(chains) = [[d.params[@varname(pred)] for d in c] for c in chains]
    @test preds(ma) == preds(mb)
    # Chains draw from independent reconstruction streams.
    @test allunique(preds(ma))
end

# A sampler JuliaBUGS has no transition_params_and_stats method for.
struct OpaqueSampler <: AbstractMCMC.AbstractSampler end
struct OpaqueTransition
    v::Float64
end
function AbstractMCMC.step(rng, ::AbstractMCMC.LogDensityModel, ::OpaqueSampler; kwargs...)
    return OpaqueTransition(0.0), nothing
end
function AbstractMCMC.step(
    rng, ::AbstractMCMC.LogDensityModel, ::OpaqueSampler, state; kwargs...
)
    return OpaqueTransition(0.1), nothing
end

@testset "sampling without a chain_type" begin
    model_def = @bugs begin
        mu ~ dnorm(0, 1)
        y ~ dnorm(mu, 1)
        doubled = 2 * mu
    end
    model = compile(model_def, (; y=0.4), (; mu=0.0))

    @testset "draws come back as ParamsWithStats" begin
        draws = Base.invokelatest(
            AbstractMCMC.sample, StableRNG(1), model, IndependentMH(), 10; progress=false
        )
        @test draws isa Vector{<:AbstractMCMC.ParamsWithStats}
        @test haskey(draws[1].params, @varname(mu))
        @test haskey(draws[1].params, @varname(doubled))
        @test keys(draws[1].stats) == (:lp,)
    end

    @testset "multiple chains give one vector per chain" begin
        chains = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(2),
            model,
            IndependentMH(),
            MCMCSerial(),
            8,
            3;
            progress=false,
        )
        @test length(chains) == 3
        @test all(c -> c isa Vector{<:AbstractMCMC.ParamsWithStats}, chains)
        @test all(c -> length(c) == 8, chains)
    end

    @testset "unknown samplers keep their raw transitions" begin
        raw = Base.invokelatest(
            AbstractMCMC.sample, StableRNG(3), model, OpaqueSampler(), 5; progress=false
        )
        @test raw isa Vector{OpaqueTransition}

        # Asking for a specific format names the method to implement.
        err = try
            Base.invokelatest(
                AbstractMCMC.sample,
                StableRNG(3),
                model,
                OpaqueSampler(),
                5;
                progress=false,
                chain_type=PWSVector,
            )
            nothing
        catch e
            e
        end
        @test err !== nothing
        @test occursin("transition_params_and_stats", sprint(showerror, err))

        # A callback that asked for nothing extracts nothing, even for unknown samplers.
        pws = AbstractMCMC.ParamsWithStats(
            AbstractMCMC.LogDensityModel(model),
            OpaqueSampler(),
            OpaqueTransition(0.0),
            nothing;
            params=false,
            stats=false,
        )
        @test isempty(pws)
    end
end
