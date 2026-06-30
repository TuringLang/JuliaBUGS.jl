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
        @test all(x -> isnan(x) || x >= 0, vec(chain[FlexiChains.Extra(:num_proposals)]))
    end

    @testset "Multivariate sampler statistics are flattened for MCMCChains" begin
        multivariate_model_def = @bugs begin
            a ~ Normal(0, 1)
            b ~ Normal(0, 1)
            y ~ Normal(a + b, 1)
        end
        multivariate_model = compile(
            multivariate_model_def, (; y=0.5), (; a=0.0, b=0.0)
        )

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
        @test chain.name_map[:internals] == [
            :lp,
            Symbol("num_proposals[1]"),
            Symbol("num_proposals[2]"),
        ]
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
end
