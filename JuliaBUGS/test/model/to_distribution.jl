@testset "to_distribution" begin
    JuliaBUGS.@bugs_primitive Normal Gamma Beta Bernoulli

    @testset "scalar model" begin
        model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
        end
        y_obs = 1.5
        model = compile(model_def, (; y=y_obs))
        d = to_distribution(model)

        @test d isa Distribution{Distributions.NamedTupleVariate{(:x,)}}
        @test Distributions.value_support(typeof(d)) === Distributions.Continuous

        rng = MersenneTwister(0)
        nt = rand(rng, d)
        @test nt isa NamedTuple{(:x,)}
        @test nt.x isa Float64

        expected = logpdf(Normal(0, 1), nt.x) + logpdf(Normal(nt.x, 1), y_obs)
        @test logpdf(d, nt) ≈ expected
        @test pdf(d, nt) ≈ exp(expected)
        @test Distributions.loglikelihood(d, nt) ≈ expected
        @test_throws ArgumentError logpdf(d, (; z=0.0))

        # no-rng rand falls back to the default RNG
        @test rand(d) isa NamedTuple{(:x,)}

        # batched rand: Distributions has no array fallback for NamedTupleVariate,
        # so without an explicit dims method this would StackOverflowError.
        samples = rand(MersenneTwister(0), d, 3)
        @test samples isa AbstractVector{<:NamedTuple{(:x,)}}
        @test length(samples) == 3
        @test rand(d, 3) isa AbstractVector{<:NamedTuple{(:x,)}}

        # rand! actually writes values: different seeds → different entries.
        buf_a = Vector{NamedTuple{(:x,),Tuple{Float64}}}(undef, 4)
        buf_b = Vector{NamedTuple{(:x,),Tuple{Float64}}}(undef, 4)
        rand!(MersenneTwister(0), d, buf_a)
        rand!(MersenneTwister(1), d, buf_b)
        @test buf_a[1].x != buf_b[1].x

        # the wrapper ignores model.transformed: same logpdf in original space
        transformed_model = JuliaBUGS.Model.settrans(model, true)
        d_t = to_distribution(transformed_model)
        @test logpdf(d_t, nt) ≈ logpdf(d, nt)
    end

    @testset "vector-valued and hierarchical model" begin
        model_def = @bugs begin
            tau ~ Gamma(2.0, 2.0)
            for i in 1:3
                x[i] ~ Normal(0, tau)
            end
            for i in 1:3
                y[i] ~ Normal(x[i], 1)
            end
        end
        y_obs = [1.0, 2.0, 3.0]
        model = compile(model_def, (; y=y_obs))
        d = to_distribution(model)

        @test d isa Distribution{Distributions.NamedTupleVariate{(:tau, :x)}}

        nt = rand(MersenneTwister(0), d)
        @test nt isa NamedTuple{(:tau, :x)}
        @test nt.x isa AbstractVector
        @test length(nt.x) == 3

        manual =
            logpdf(Gamma(2.0, 2.0), nt.tau) +
            sum(logpdf(Normal(0, nt.tau), xi) for xi in nt.x) +
            sum(logpdf(Normal(nt.x[i], 1), y_obs[i]) for i in eachindex(y_obs))
        @test logpdf(d, nt) ≈ manual
    end

    @testset "partially observed array" begin
        model_def = @bugs begin
            for i in 1:4
                x[i] ~ Normal(0, 1)
            end
        end
        model = compile(model_def, (; x=[missing, 1.0, missing, 2.0]))
        d = to_distribution(model)

        nt = rand(MersenneTwister(0), d)
        @test nt.x[2] == 1.0
        @test nt.x[4] == 2.0
        # logpdf is the joint over both stochastic params and observed data
        manual = sum(logpdf(Normal(0, 1), v) for v in nt.x)
        @test logpdf(d, nt) ≈ manual
    end

    @testset "mixed discrete/continuous" begin
        model_def = @bugs begin
            p ~ Beta(2, 2)
            z ~ Bernoulli(p)
        end
        model = compile(model_def, NamedTuple())
        d = to_distribution(model)
        nt = rand(MersenneTwister(0), d)
        @test nt isa NamedTuple{(:p, :z)}
        manual = logpdf(Beta(2, 2), nt.p) + logpdf(Bernoulli(nt.p), nt.z)
        @test logpdf(d, nt) ≈ manual
    end
end
