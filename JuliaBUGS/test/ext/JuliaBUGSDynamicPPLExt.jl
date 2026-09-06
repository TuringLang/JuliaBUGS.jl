using DynamicPPL
using DynamicPPL:
    LogDensityFunction, InitFromUniform, LinkAll, getlogjoint_internal, logjoint
using ADTypes: AutoForwardDiff, AutoMooncake
using JuliaBUGS: to_marginal, recover_discrete
using JuliaBUGS.Model: _constrain
using AbstractPPL: @varname
using Statistics: mean

@testset "DynamicPPL extension" begin
    source = """
    model {
      for (k in 1:2) {
        mu[k] ~ dnorm(0, 0.01)
        sigma[k] ~ dexp(1)
      }
      for (i in 1:N) {
        z[i] ~ dcat(w[1:2])
        y[i] ~ dnorm(mu[z[i]], 1 / (sigma[z[i]] * sigma[z[i]]))
      }
    }
    """
    y = [-3.1, -2.8, -3.0, -2.9, -3.2, -3.1, 3.2, 2.9, 3.1, 3.0, 2.8, 3.1]
    data = (; N=length(y), w=[0.5, 0.5], y=y)
    d = to_marginal(source; data)

    DynamicPPL.@model function embed(d, yobs)
        theta ~ d
        yobs ~ Normal(sum(theta), 1)
        return theta
    end
    model = embed(d, 0.4)

    @testset "prior draws through the tilde" begin
        theta = model()
        @test length(theta) == length(d)
        @test insupport(d, theta)
        @test length(NamedTuple(rand(StableRNG(1), model)).theta) == length(d)
    end

    @testset "log joint in constrained space" begin
        x = rand(StableRNG(2), d)
        expected = logpdf(d, x) + logpdf(Normal(sum(x), 1), 0.4)
        @test logjoint(model, (; theta=x)) ≈ expected
        invalid = copy(x)
        invalid[d.constrained_offsets[@varname(sigma[1])]] = -1.0
        @test logjoint(model, (; theta=invalid)) == -Inf
    end

    # In unconstrained space the embedded density is the BUGS marginal log density as
    # JuliaBUGS states it, Jacobian included, plus the downstream term.
    u = [0.3, -0.2, 0.1, -0.4]
    expected(v) =
        LogDensityProblems.logdensity(d.model, v) +
        logpdf(Normal(sum(_constrain(d, v)), 1), 0.4)
    ldf = LogDensityFunction(model; adtype=AutoForwardDiff())

    @testset "log density and gradient in unconstrained space" begin
        @test LogDensityProblems.dimension(ldf) == 4
        @test LogDensityProblems.logdensity(ldf, u) ≈ expected(u)
        value, gradient = LogDensityProblems.logdensity_and_gradient(ldf, u)
        @test value ≈ expected(u)
        @test gradient ≈ ForwardDiff.gradient(expected, u)
        uniform_u = rand(ldf, InitFromUniform())
        @test length(uniform_u) == 4
        @test all(-2 .<= uniform_u .<= 2)
    end

    @testset "Mooncake agrees with ForwardDiff" begin
        mooncake_ldf = LogDensityFunction(
            model, getlogjoint_internal, LinkAll(); adtype=AutoMooncake(; config=nothing)
        )
        value, gradient = LogDensityProblems.logdensity_and_gradient(mooncake_ldf, u)
        @test value ≈ expected(u)
        @test gradient ≈ ForwardDiff.gradient(expected, u)
    end

    @testset "source written inside the model" begin
        DynamicPPL.@model function embed_source(source, data, yobs)
            theta ~ to_marginal(source; data)
            yobs ~ Normal(sum(theta), 1)
            return theta
        end
        x = rand(StableRNG(3), d)
        @test logjoint(embed_source(source, data, 0.4), (; theta=x)) ≈
            logjoint(model, (; theta=x))
    end

    @testset "NUTS on the continuous parameters recovers the components" begin
        rng = StableRNG(4)
        chain = sample(
            rng,
            AbstractMCMC.LogDensityModel(ldf),
            NUTS(0.8),
            500;
            n_adapts=250,
            discard_initial=250,
            initial_params=u,
            progress=false,
        )
        thetas = [_constrain(d, t.z.θ) for t in chain]
        mus = sort([
            mean(t[d.constrained_offsets[@varname(mu[k])]] for t in thetas) for k in 1:2
        ])
        @test isapprox(mus, [-3.0, 3.0]; atol=0.4)
        # The latents come back consistent with the recovered means.
        env = recover_discrete(rng, d, thetas[end])
        z = [AbstractPPL.getvalue(env, @varname(z[i])) for i in 1:length(y)]
        @test allequal(z[1:6])
        @test allequal(z[7:12])
        @test z[1] != z[7]
    end
end
