using DynamicPPL

@testset "JuliaBUGSDynamicPPLExt" begin
    VB = Bijectors.VectorBijectors

    @testset "VectorBijectors round-trip (scalar / vector / partial array)" begin
        # scalar free parameter
        m1 = compile(
            (@bugs begin
                x ~ dnorm(0, 1)
                y ~ dnorm(x, 1)
            end),
            (; y=1.0),
        )
        d1 = to_distribution(m1)
        @test VB.vec_length(d1) == 1
        @test VB.to_vec(d1)((x=0.3,)) == [0.3]
        @test VB.from_vec(d1)([0.3]) == (x=0.3,)

        # fully-stochastic vector parameter
        m2 = compile(
            (@bugs begin
                for i in 1:3
                    x[i] ~ dnorm(0, 1)
                end
            end),
            NamedTuple(),
        )
        d2 = to_distribution(m2)
        @test VB.vec_length(d2) == 3
        @test VB.to_vec(d2)((x=[0.1, 0.2, 0.3],)) == [0.1, 0.2, 0.3]
        @test VB.from_vec(d2)([0.1, 0.2, 0.3]) == (x=[0.1, 0.2, 0.3],)

        # partially-observed array: the variate carries the full-shaped array (observed
        # slots included), so vec_length is the full length and the round-trip is total.
        m3 = compile(
            (@bugs begin
                for i in 1:3
                    x[i] ~ dnorm(0, 1)
                end
            end),
            (; x=[1.0, missing, missing]),
        )
        d3 = to_distribution(m3)
        @test VB.vec_length(d3) == 3
        @test VB.from_vec(d3)(VB.to_vec(d3)((x=[1.0, 0.5, -0.5],))) == (x=[1.0, 0.5, -0.5],)
    end

    @testset "embedded in a DynamicPPL @model: logjoint matches logpdf" begin
        bugs = compile(
            (@bugs begin
                x ~ dnorm(0, 1)
                y ~ dnorm(x, 1)
            end),
            (; y=1.0),
        )
        d = to_distribution(bugs)

        DynamicPPL.@model function outer()
            theta ~ d
            z ~ Normal(theta.x, 1)
        end

        # forward / ancestral sampling works (would StackOverflow without the dims-rand, and
        # would error at `to_vec` without the extension).
        @test (rand(outer()); true)

        model = outer() | (; z=0.5)
        theta_val = (x=0.3,)
        params = (theta=theta_val,)
        # theta contributes the full BUGS joint as the *prior*; z is the outer likelihood.
        @test DynamicPPL.logprior(model, params) ≈ logpdf(d, theta_val)
        @test DynamicPPL.loglikelihood(model, params) ≈ logpdf(Normal(0.3, 1), 0.5)
        @test DynamicPPL.logjoint(model, params) ≈
            logpdf(d, theta_val) + logpdf(Normal(0.3, 1), 0.5)
    end

    @testset "vector parameter through the @model logjoint" begin
        m = compile(
            (@bugs begin
                for i in 1:3
                    x[i] ~ dnorm(0, 1)
                end
            end),
            NamedTuple(),
        )
        d = to_distribution(m)
        DynamicPPL.@model outer_vec() = (theta ~ d)
        xv = (x=[0.1, 0.2, 0.3],)
        @test DynamicPPL.logjoint(outer_vec(), (theta=xv,)) ≈ logpdf(d, xv)
    end

    @testset "partially-observed array: logjoint matches logpdf; observed slot inert" begin
        m = compile(
            (@bugs begin
                for i in 1:3
                    x[i] ~ dnorm(0, 1)
                end
            end),
            (; x=[1.0, missing, missing]),
        )
        d = to_distribution(m)
        DynamicPPL.@model outer_arr() = (theta ~ d)

        full = (x=[1.0, 0.5, -0.5],)
        @test DynamicPPL.logjoint(outer_arr(), (theta=full,)) ≈ logpdf(d, full)
        # the observed slot is inert through the DynamicPPL path too
        tampered = (x=[999.0, 0.5, -0.5],)
        @test DynamicPPL.logjoint(outer_arr(), (theta=tampered,)) ≈
            DynamicPPL.logjoint(outer_arr(), (theta=full,))
    end
end
