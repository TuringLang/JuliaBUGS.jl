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

        # rand! writes the whole buffer, returns it, and fills with distinct draws.
        buf_a = Vector{NamedTuple{(:x,),Tuple{Float64}}}(undef, 4)
        buf_b = Vector{NamedTuple{(:x,),Tuple{Float64}}}(undef, 4)
        @test rand!(MersenneTwister(0), d, buf_a) === buf_a
        rand!(MersenneTwister(1), d, buf_b)
        @test all(b -> b isa NamedTuple{(:x,)}, buf_a)
        @test allunique(getfield.(buf_a, :x))   # ancestral draws differ within a buffer
        @test buf_a[1].x != buf_b[1].x

        # loglikelihood over a vector sums the joint; empty input is 0.0; show is exercised.
        @test Distributions.loglikelihood(d, [nt, nt]) ≈ 2 * logpdf(d, nt)
        @test Distributions.loglikelihood(d, NamedTuple{(:x,),Tuple{Float64}}[]) == 0.0
        @test occursin("BUGSModelDistribution", sprint(show, d))

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

        # rand bakes the model's observed data into the observed slots.
        nt = rand(MersenneTwister(0), d)
        @test nt.x[2] == 1.0
        @test nt.x[4] == 2.0

        # logpdf is the full joint, but the observed slots are scored against the MODEL's
        # data, never against the caller's input: only the free parameters (x[1], x[3]) are
        # read from the supplied NamedTuple. So logpdf is invariant to whatever sits in the
        # observed slots (x[2], x[4]).
        free1, free3 = nt.x[1], nt.x[3]
        expected =
            logpdf(Normal(0, 1), free1) +
            logpdf(Normal(0, 1), free3) +    # free parameters x[1], x[3]
            logpdf(Normal(0, 1), 1.0) +
            logpdf(Normal(0, 1), 2.0)        # observed data x[2], x[4] (from the model)
        @test logpdf(d, nt) ≈ expected

        # Tampering with the observed slots must not change the density (the bug: it did).
        tampered = (; x=[free1, 999.0, free3, -888.0])
        @test logpdf(d, tampered) ≈ expected
        @test logpdf(d, tampered) ≈ logpdf(d, nt)

        # logpdf must not corrupt the model's stored data.
        @test model.evaluation_env.x[2] == 1.0
        @test model.evaluation_env.x[4] == 2.0
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
        # mixed support currently reduces to Continuous (discreteness of z is lost).
        @test Distributions.value_support(typeof(d)) === Distributions.Continuous
    end

    @testset "logpdf/rand leave the model unmutated (isolation)" begin
        # A logical/deterministic array node (m) is the case that regressed: logpdf must
        # not write recomputed deterministic values back into the wrapped model's env.
        model_def = @bugs begin
            tau ~ Gamma(2.0, 2.0)
            for i in 1:3
                m[i] = tau * i
                y[i] ~ Normal(m[i], 1)
            end
        end
        model = compile(model_def, (; y=[1.0, 2.0, 3.0]))
        d = to_distribution(model)
        m_before = copy(model.evaluation_env.m)
        tau_before = model.evaluation_env.tau

        lp = logpdf(d, (; tau=5.0))
        @test model.evaluation_env.m == m_before     # deterministic node not corrupted
        @test model.evaluation_env.tau == tau_before
        @test logpdf(d, (; tau=5.0)) == lp           # no leaked state across calls

        rand(MersenneTwister(0), d)
        @test model.evaluation_env.m == m_before
    end

    @testset "fully observed model (empty parameter set)" begin
        model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
        end
        model = compile(model_def, (; x=0.3, y=1.0))
        d = to_distribution(model)
        @test d isa Distribution{Distributions.NamedTupleVariate{()}}
        @test Distributions.value_support(typeof(d)) === Distributions.Continuous
        @test rand(MersenneTwister(0), d) == NamedTuple()
        manual = logpdf(Normal(0, 1), 0.3) + logpdf(Normal(0.3, 1), 1.0)
        @test logpdf(d, NamedTuple()) ≈ manual
    end

    @testset "generated-mode model keeps stochastic generated quantities" begin
        model_def = @bugs begin
            mu ~ Normal(0, 1)
            y ~ Normal(mu, 1)
            z ~ Normal(mu, 1)
        end
        model = compile(model_def, (; y=0.5))
        generated_model = JuliaBUGS.Model.set_evaluation_mode(
            model, JuliaBUGS.Model.UseGeneratedLogDensityFunction()
        )
        @test Set(JuliaBUGS.Model.parameters(generated_model)) ==
            Set(JuliaBUGS.Model.parameters(model))

        distribution = @test_logs (:warn,) match_mode = :any to_distribution(
            generated_model
        )
        @test distribution isa Distribution{Distributions.NamedTupleVariate{(:mu, :z)}}

        parameter_values = (mu=0.1, z=0.2)
        expected_logdensity =
            logpdf(Normal(0, 1), parameter_values.mu) +
            logpdf(Normal(parameter_values.mu, 1), 0.5) +
            logpdf(Normal(parameter_values.mu, 1), parameter_values.z)
        @test logpdf(distribution, parameter_values) ≈ expected_logdensity
        @test_throws ArgumentError logpdf(distribution, (; mu=parameter_values.mu))
    end

    @testset "multivariate parameter nodes" begin
        # A single multivariate stochastic node packs into one NamedTuple field.
        @testset "ddirich (simplex-valued)" begin
            model_def = @bugs begin
                w[1:3] ~ ddirich(alpha[1:3])
            end
            alpha = [1.0, 2.0, 3.0]
            d = to_distribution(compile(model_def, (; alpha=alpha)))
            @test d isa Distribution{Distributions.NamedTupleVariate{(:w,)}}
            nt = rand(MersenneTwister(0), d)
            @test nt.w isa AbstractVector && length(nt.w) == 3
            @test sum(nt.w) ≈ 1
            @test logpdf(d, nt) ≈ logpdf(ddirich(alpha), nt.w)
        end

        @testset "dmnorm (vector-valued)" begin
            model_def = @bugs begin
                x[1:2] ~ dmnorm(mu[:], Tau[:, :])
            end
            mu = [0.0, 1.0]
            Tau = [2.0 0.0; 0.0 4.0]
            d = to_distribution(compile(model_def, (; mu=mu, Tau=Tau)))
            nt = rand(MersenneTwister(0), d)
            @test nt.x isa AbstractVector && length(nt.x) == 2
            @test logpdf(d, nt) ≈ logpdf(dmnorm(mu, Tau), nt.x)
        end
    end

    @testset "warns only when evaluation_mode is not UseGraph" begin
        model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
        end
        model = compile(model_def, (; y=1.5))
        # default UseGraph model: the wrapper is constructed silently.
        @test_logs to_distribution(model)
        # explicitly switching modes surfaces a one-time warning (the wrapper still
        # always uses graph evaluation, so logpdf may differ from this mode).
        gen = JuliaBUGS.Model.set_evaluation_mode(
            model, JuliaBUGS.Model.UseGeneratedLogDensityFunction()
        )
        @test !(gen.evaluation_mode isa JuliaBUGS.Model.UseGraph)
        @test_logs (:warn,) match_mode = :any to_distribution(gen)
    end
end

@testset "BUGSModel prior draws" begin
    model_def = @bugs begin
        p ~ Beta(2, 3)
        y ~ Bernoulli(p)
        predictive ~ Exponential(1)
        doubled = 2 * p
    end
    model = compile(model_def, (; y=1))

    original_env = deepcopy(model.evaluation_env)
    draw = rand(MersenneTwister(42), model)

    @test draw isa AbstractPPL.VarNamedTuple
    @test Set(keys(draw)) == Set(JuliaBUGS.parameters(model))
    @test length(draw) == length(JuliaBUGS.parameters(model))
    @test haskey(draw, @varname(p))
    @test haskey(draw, @varname(predictive))
    @test !haskey(draw, @varname(y))
    @test !haskey(draw, @varname(doubled))
    @test draw == rand(MersenneTwister(42), model)
    @test model.evaluation_env == original_env

    transformed_model = JuliaBUGS.settrans(model, true)
    transformed_draw = rand(MersenneTwister(7), transformed_model)
    @test 0 < transformed_draw[@varname(p)] < 1
    @test transformed_draw[@varname(predictive)] > 0

    partial_model = compile(
        @bugs(
            begin
                beta[1:2] ~ MvNormal(zeros(2), Diagonal(ones(2)))
                for i in 1:3
                    x[i] ~ Normal(0, 1)
                end
                y ~ Normal(beta[1] + x[1], 1)
                pred = sum(beta[1:2]) + sum(x[1:3])
            end
        ),
        (; x=Union{Missing,Float64}[missing, 2.0, missing], y=0.0),
    )
    partial_draw = rand(MersenneTwister(9), partial_model)
    @test Set(keys(partial_draw)) ==
        Set([@varname(beta[1]), @varname(beta[2]), @varname(x[1]), @varname(x[3])])
    @test length(partial_draw[@varname(beta[1:2])]) == 2
    @test !haskey(partial_draw, @varname(x[2]))
    @test !haskey(partial_draw, @varname(pred))
end
