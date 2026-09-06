using JuliaBUGS: to_marginal, recover_discrete
using JuliaBUGS.Model: BUGSMarginalDistribution
using AbstractPPL: @varname

const MIXTURE_SOURCE = """
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
const MIXTURE_Y = [-3.1, -2.8, 3.2, 2.9, -3.0, 3.1]
const MIXTURE_DATA = (; N=length(MIXTURE_Y), w=[0.5, 0.5], y=MIXTURE_Y)

# The constrained vector for given component means and scales, whatever order the
# marginalization cache put the parameters in.
function mixture_vector(d, mu, sigma)
    x = zeros(length(d))
    for k in 1:2
        x[d.constrained_offsets[@varname(mu[k])]] = mu[k]
        x[d.constrained_offsets[@varname(sigma[k])]] = sigma[k]
    end
    return x
end

function mixture_marginal_logjoint(mu, sigma)
    lp = sum(logpdf(Normal(0, 10), mu)) + sum(logpdf(Exponential(1), sigma))
    for yi in MIXTURE_Y
        lp += log(
            0.5 * pdf(Normal(mu[1], sigma[1]), yi) + 0.5 * pdf(Normal(mu[2], sigma[2]), yi)
        )
    end
    return lp
end

@testset "to_marginal" begin
    d = to_marginal(MIXTURE_SOURCE; data=MIXTURE_DATA)
    @test d isa BUGSMarginalDistribution
    @test d isa Distributions.ContinuousMultivariateDistribution
    @test length(d) == 4
    @test d.model.transformed
    @test d.model.evaluation_mode isa JuliaBUGS.UseAutoMarginalization

    @testset "logpdf is the constrained marginal log joint" begin
        mu = [-2.5, 3.5]
        sigma = [0.8, 1.2]
        x = mixture_vector(d, mu, sigma)
        @test logpdf(d, x) ≈ mixture_marginal_logjoint(mu, sigma)
        @test insupport(d, x)
    end

    @testset "outside the support" begin
        x = mixture_vector(d, [-2.5, 3.5], [-0.8, 1.2])
        @test !insupport(d, x)
        @test logpdf(d, x) == -Inf
        @test_throws DimensionMismatch logpdf(d, zeros(3))
    end

    @testset "rand draws the whole model and returns the continuous parameters" begin
        rng = StableRNG(1)
        x = rand(rng, d)
        @test length(x) == 4
        @test insupport(d, x)
        @test x[d.constrained_offsets[@varname(sigma[1])]] > 0
        @test x[d.constrained_offsets[@varname(sigma[2])]] > 0
        xs = rand(rng, d, 3)
        @test size(xs) == (4, 3)
        @test all(insupport(d, xs[:, j]) for j in 1:3)
    end

    @testset "the string form is cached and agrees with the model form" begin
        @test to_marginal(MIXTURE_SOURCE; data=MIXTURE_DATA) === d
        model_def = JuliaBUGS.Parser._bugs_string_input(MIXTURE_SOURCE, true, false)
        d2 = to_marginal(compile(model_def, MIXTURE_DATA))
        x = mixture_vector(d, [-2.5, 3.5], [0.8, 1.2])
        @test logpdf(d2, x) ≈ logpdf(d, x)
    end

    @testset "recover_discrete draws the latents from their conditional" begin
        # Well separated components with tight scales, so each observation's
        # component is all but certain.
        x = mixture_vector(d, [-3.0, 3.0], [0.3, 0.3])
        env = recover_discrete(StableRNG(2), d, x)
        z = [AbstractPPL.getvalue(env, @varname(z[i])) for i in 1:length(MIXTURE_Y)]
        @test all(zi in (1, 2) for zi in z)
        @test z[1] == z[2] == z[5]
        @test z[3] == z[4] == z[6]
        @test z[1] != z[3]
        # The continuous parameters come back as given.
        @test AbstractPPL.getvalue(env, @varname(mu[1])) ≈ -3.0
        @test AbstractPPL.getvalue(env, @varname(sigma[2])) ≈ 0.3
    end

    @testset "an unbounded discrete parameter cannot be marginalized" begin
        source = """
        model {
          lambda ~ dgamma(1, 1)
          n ~ dpois(lambda)
        }
        """
        err = try
            to_marginal(source; data=(;))
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("n has unbounded support", err.msg)
    end
end
