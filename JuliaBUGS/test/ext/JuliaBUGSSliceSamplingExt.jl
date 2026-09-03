using JuliaBUGS: Gibbs

@testset "SliceSampling extension" begin
    model_def = @bugs begin
        θ ~ Normal(0, 1)
        y ~ Normal(θ, 1)
        doubled = 2 * θ
    end
    model = compile(model_def, (; y=0.25), (; θ=0.0))

    @testset "MCMCChains output and default initialization" begin
        chain = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(1234),
            model,
            SliceSampling.SliceSteppingOut(1.0),
            40;
            progress=false,
            chain_type=Chains,
        )

        @test chain isa Chains
        @test size(chain, 1) == 40
        @test :θ in chain.name_map[:parameters]
        @test :doubled in chain.name_map[:parameters]
        @test chain.name_map[:internals] == [:lp, :num_proposals]
        @test all(isfinite, vec(chain[:θ].data))
        @test all(isfinite, vec(chain[:lp].data))
        @test all(x -> isnan(x) || x >= 0, vec(chain[:num_proposals].data))
    end

    @testset "FlexiChains output" begin
        chain = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(5678),
            model,
            SliceSampling.SliceSteppingOut(1.0),
            30;
            progress=false,
            chain_type=VNChain,
        )

        @test chain isa VNChain
        @test size(chain) == (30, 1)
        @test Set(FlexiChains.parameters(chain)) == Set([@varname(θ), @varname(doubled)])
        @test Set(FlexiChains.get_name.(FlexiChains.extras(chain))) ==
            Set([:lp, :num_proposals])
        @test all(isfinite, vec(chain[FlexiChains.Extra(:lp)]))
        # The initial transition reports no `num_proposals`; FlexiChains keeps that absence
        # as `missing` rather than padding it.
        @test all(
            x -> ismissing(x) || x >= 0, vec(chain[FlexiChains.Extra(:num_proposals)])
        )
    end

    @testset "Multivariate sampler statistics are flattened for MCMCChains" begin
        multivariate_model_def = @bugs begin
            a ~ Normal(0, 1)
            b ~ Normal(0, 1)
            y ~ Normal(a + b, 1)
        end
        multivariate_model = compile(multivariate_model_def, (; y=0.5), (; a=0.0, b=0.0))

        chain = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(2468),
            multivariate_model,
            SliceSampling.RandPermGibbs(SliceSampling.SliceSteppingOut(1.0)),
            35;
            progress=false,
            chain_type=Chains,
        )

        @test chain isa Chains
        @test Set([:a, :b]) ⊆ Set(chain.name_map[:parameters])
        @test chain.name_map[:internals] ==
            [:lp, Symbol("num_proposals[1]"), Symbol("num_proposals[2]")]
        @test all(isfinite, vec(chain[:lp].data))
    end

    @testset "Slice samplers can be used inside JuliaBUGS.Gibbs" begin
        gibbs_model_def = @bugs begin
            a ~ Normal(0, 1)
            b ~ Normal(0, 1)
            y ~ Normal(a + b, 1)
        end
        gibbs_model = compile(gibbs_model_def, (; y=0.5), (; a=0.0, b=0.0))
        sampler_map = OrderedDict(
            @varname(a) => SliceSampling.SliceSteppingOut(1.0),
            @varname(b) => SliceSampling.SliceSteppingOut(1.0),
        )
        gibbs = Gibbs(gibbs_model, sampler_map)

        logdensitymodel = AbstractMCMC.LogDensityModel(gibbs_model)
        _, state = AbstractMCMC.step(StableRNG(1357), logdensitymodel, gibbs)
        _, state = AbstractMCMC.step(StableRNG(1358), logdensitymodel, gibbs, state)
        @test all(
            sub_state -> haskey(sub_state.transition.info, :num_proposals),
            values(state.sub_states),
        )

        chain = Base.invokelatest(
            AbstractMCMC.sample,
            StableRNG(1357),
            gibbs_model,
            gibbs,
            50;
            progress=false,
            chain_type=Chains,
        )

        @test chain isa Chains
        @test size(chain, 1) == 50
        @test Set([:a, :b]) ⊆ Set(chain.name_map[:parameters])
        @test all(isfinite, vec(chain[:a].data))
        @test all(isfinite, vec(chain[:b].data))
    end

    @testset "Gibbs targets continuous full conditionals" begin
        conditional_model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
            z ~ Normal(y, 1)
        end
        conditional_model = compile(conditional_model_def, (; z=1.0), (; x=0.0, y=0.0))
        gibbs = Gibbs(
            conditional_model,
            OrderedDict(
                @varname(x) => SliceSampling.SliceSteppingOut(1.0),
                @varname(y) => SliceSampling.SliceSteppingOut(1.0),
            ),
        )
        chain = AbstractMCMC.sample(
            StableRNG(9753),
            conditional_model,
            gibbs,
            5_000;
            discard_initial=500,
            chain_type=Chains,
            progress=false,
        )

        @test mean(chain[:x]) ≈ 1 / 3 atol = 0.06
        @test mean(chain[:y]) ≈ 2 / 3 atol = 0.06
    end

    @testset "Finite discrete blocks use exact Gibbs updates" begin
        discrete_model_def = @bugs begin
            k ~ Bernoulli(0.5)
            y ~ Bernoulli(0.1 + 0.8 * k)
        end
        discrete_model = compile(discrete_model_def, (; y=1), (; k=0))
        gibbs = Gibbs(
            discrete_model, OrderedDict(@varname(k) => SliceSampling.SliceSteppingOut(1.0))
        )
        @test only(values(gibbs.sampler_map)) isa JuliaBUGS.EnumeratedSampler
    end
end
