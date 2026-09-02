using AdvancedMH:
    AbstractTransition, Ensemble, RWMH, RobustAdaptiveMetropolis, StaticMH, StretchProposal
using JuliaBUGS: @model, EnumeratedSampler, Gibbs, gibbs_internal

@testset "AdvancedMH" begin
    @testset "RWMH targets a constrained posterior" begin
        @model function beta_bernoulli((; p, y), N)
            p ~ Beta(2, 2)
            for i in 1:N
                y[i] ~ Bernoulli(p)
            end
        end

        model = beta_bernoulli((; y=zeros(Int, 10)), 10)
        sampler = RWMH([Normal(0, 0.8)])
        draws = sample(
            StableRNG(2026),
            model,
            sampler,
            30_000;
            initial_params=JuliaBUGS.getparams(model),
            discard_initial=5_000,
            progress=false,
        )

        posterior_mean = 2 / 14
        @test mean(d.params[@varname(p)] for d in draws) ≈ posterior_mean atol = 0.015
        @test all(d -> keys(d.stats) == (:lp, :accepted), draws)
    end

    @testset "Gibbs advances AdvancedMH on the first sweep" begin
        model_def = @bugs begin
            mu ~ Normal(0, 1)
            y ~ Normal(mu - mu, 1)
        end
        model = compile(model_def, (; y=0.0), (; mu=10.0))
        sampler = StaticMH([Normal(0, 1)])

        env, state = gibbs_internal(StableRNG(11), model, sampler)
        @test state isa AbstractTransition
        @test state.params == JuliaBUGS.getparams(model, env)
        @test state.accepted
        @test env.mu != 10.0

        next_env, next_state = gibbs_internal(StableRNG(12), model, sampler, state)
        @test next_state isa AbstractTransition
        @test next_state.params == JuliaBUGS.getparams(model, next_env)
    end

    @testset "StaticMH supports discrete parameters" begin
        model_def = @bugs begin
            k ~ Categorical(prior)
            for i in 1:N
                y[i] ~ Normal(means[k], 0.1)
            end
        end
        model = compile(
            model_def, (; prior=[0.2, 0.3, 0.5], means=[-1.0, 0.0, 1.0], N=20, y=ones(20))
        )
        sampler = StaticMH([Categorical([0.2, 0.3, 0.5])])
        draws = sample(
            StableRNG(13),
            model,
            sampler,
            1_000;
            initial_params=JuliaBUGS.getparams(model),
            progress=false,
        )

        @test all(d -> d.params[@varname(k)] in 1:3, draws)
        @test count(d -> d.params[@varname(k)] == 3, draws) > 900
    end

    @testset "Gibbs targets a discrete full conditional" begin
        model_def = @bugs begin
            x ~ Bernoulli(0.5)
            y ~ Bernoulli(0.1 + 0.8 * x)
            z ~ Bernoulli(0.1 + 0.8 * y)
        end
        model = compile(model_def, (; z=1), (; x=0, y=0))
        gibbs = Gibbs(
            model,
            OrderedDict(
                @varname(x) => EnumeratedSampler(), @varname(y) => EnumeratedSampler()
            ),
        )
        @test all(sampler -> sampler isa EnumeratedSampler, values(gibbs.sampler_map))
        chain = sample(
            StableRNG(15),
            model,
            gibbs,
            20_000;
            discard_initial=2_000,
            chain_type=MCMCChains.Chains,
            progress=false,
        )

        x = vec(chain[:x].data)
        y = vec(chain[:y].data)
        @test mean(x[y .== 0]) ≈ 0.1 atol = 0.03
        @test mean(x[y .== 1]) ≈ 0.9 atol = 0.03
    end

    @testset "Gibbs retargets adaptive MH state" begin
        model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
            z ~ Normal(y, 1)
        end
        model = compile(model_def, (; z=1.0), (; x=0.0, y=0.0))
        gibbs = Gibbs(
            model,
            OrderedDict(
                @varname(x) => RobustAdaptiveMetropolis(),
                @varname(y) => RobustAdaptiveMetropolis(),
            ),
        )
        chain = sample(
            StableRNG(16), model, gibbs, 10; chain_type=MCMCChains.Chains, progress=false
        )

        @test all(isfinite, chain[:x])
        @test all(isfinite, chain[:y])
        @test_throws ArgumentError Gibbs(
            model,
            OrderedDict(
                [@varname(x), @varname(y)] =>
                    Ensemble(4, StretchProposal(MvNormal(zeros(2), I))),
            ),
        )
    end

    @testset "output formats" begin
        model_def = @bugs begin
            mu ~ Normal(0, 1)
            y ~ Normal(mu, 0.1)
        end
        model = compile(model_def, (; y=1.0))
        sampler = RWMH([Normal(0, 0.2)])
        chain = sample(
            StableRNG(14),
            model,
            sampler,
            100;
            initial_params=JuliaBUGS.getparams(model),
            chain_type=MCMCChains.Chains,
            progress=false,
        )

        @test chain isa MCMCChains.Chains
        @test chain.name_map[:parameters] == [:mu]
        @test chain.name_map[:internals] == [:lp, :accepted]

        named_draws = sample(
            StableRNG(17),
            model,
            sampler,
            5;
            initial_params=JuliaBUGS.getparams(model),
            chain_type=Vector{NamedTuple},
            progress=false,
        )
        @test named_draws isa Vector{<:NamedTuple}
        @test keys(first(named_draws)) == (:param_1, :lp)

        raw_draws = sample(
            StableRNG(17),
            model,
            sampler,
            5;
            initial_params=JuliaBUGS.getparams(model),
            chain_type=Vector{AbstractTransition},
            progress=false,
        )
        @test raw_draws isa Vector{<:AbstractTransition}
    end
end
