using JuliaBUGS
using JuliaBUGS: @model, @of

@testset "model macro" begin
    # Test with inline of annotations (Interface 1)
    @testset "Interface 1: Inline of annotations" begin

        #! format: off
        @model function seeds(
            (; r::of(Array, Int, 21),
               b::of(Array, 21),
               alpha0::of(Real),
               alpha1::of(Real),
               alpha2::of(Real),
               alpha12::of(Real),
               tau::of(Real, 0, nothing)
            ), 
            x1, x2, N, n
        )
            for i in 1:N
                r[i] ~ dbin(p[i], n[i])
                b[i] ~ dnorm(0.0, tau)
                p[i] = logistic(
                    alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
                )
            end
            alpha0 ~ dnorm(0.0, 1.0E-6)
            alpha1 ~ dnorm(0.0, 1.0E-6)
            alpha2 ~ dnorm(0.0, 1.0E-6)
            alpha12 ~ dnorm(0.0, 1.0E-6)
            tau ~ dgamma(0.001, 0.001)
            sigma = 1 / sqrt(tau)
        end
        #! format: on

        data = JuliaBUGS.BUGSExamples.seeds.data

        # Test with no observations
        m1 = seeds((;), data.x1, data.x2, data.N, data.n)
        @test m1 isa JuliaBUGS.BUGSModel

        # Test with observations
        m2 = seeds((r=data.r,), data.x1, data.x2, data.N, data.n)
        @test m2 isa JuliaBUGS.BUGSModel
    end

    # Test with external type definition (Interface 2)
    @testset "Interface 2: External type definition" begin
        SeedsParams = @of(
            r = of(Array, Int, 21),
            b = of(Array, 21),
            alpha0 = of(Real),
            alpha1 = of(Real),
            alpha2 = of(Real),
            alpha12 = of(Real),
            tau = of(Real, 0, nothing)
        )

        #! format: off
        @model function seeds2(
            (; r, b, alpha0, alpha1, alpha2, alpha12, tau)::SeedsParams, 
            x1, x2, N, n
        )
            for i in 1:N
                r[i] ~ dbin(p[i], n[i])
                b[i] ~ dnorm(0.0, tau)
                p[i] = logistic(
                    alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
                )
            end
            alpha0 ~ dnorm(0.0, 1.0E-6)
            alpha1 ~ dnorm(0.0, 1.0E-6)
            alpha2 ~ dnorm(0.0, 1.0E-6)
            alpha12 ~ dnorm(0.0, 1.0E-6)
            tau ~ dgamma(0.001, 0.001)
            sigma = 1 / sqrt(tau)
        end
        #! format: on

        data = JuliaBUGS.BUGSExamples.seeds.data

        # Test with empty NamedTuple (no observations)
        m1 = seeds2((;), data.x1, data.x2, data.N, data.n)
        @test m1 isa JuliaBUGS.BUGSModel

        # Test with observations
        m2 = seeds2((r=data.r,), data.x1, data.x2, data.N, data.n)
        @test m2 isa JuliaBUGS.BUGSModel
    end

    # Test error handling
    @testset "Error handling" begin
        # Try leaving out a stochastic variable (tau is used but not declared)
        @test_throws ErrorException begin
            #! format: off
            @model function bad_seeds(
                (; r::of(Array, Int, 21),
                   b::of(Array, 21),
                   alpha0::of(Real),
                   alpha1::of(Real),
                   alpha2::of(Real),
                   alpha12::of(Real)
                   # tau is missing
                ), 
                x1, x2, N, n
            )
                for i in 1:N
                    r[i] ~ dbin(p[i], n[i])
                    b[i] ~ dnorm(0.0, tau)  # tau is used here but not declared
                    p[i] = logistic(
                        alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
                    )
                end
                alpha0 ~ dnorm(0.0, 1.0E-6)
                alpha1 ~ dnorm(0.0, 1.0E-6)
                alpha2 ~ dnorm(0.0, 1.0E-6)
                alpha12 ~ dnorm(0.0, 1.0E-6)
                tau ~ dgamma(0.001, 0.001)
                sigma = 1 / sqrt(tau)
            end
            #! format: on
        end

        # Try leaving out a constant variable
        @test_throws ErrorException begin
            #! format: off
            @model function bad_seeds2(
                (; r::of(Array, Int, 21),
                   b::of(Array, 21),
                   alpha0::of(Real),
                   alpha1::of(Real),
                   alpha2::of(Real),
                   alpha12::of(Real),
                   tau::of(Real, 0, nothing)
                ), 
                x2, N, n  # x1 is missing
            )
                for i in 1:N
                    r[i] ~ dbin(p[i], n[i])
                    b[i] ~ dnorm(0.0, tau)
                    p[i] = logistic(
                        alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]  # x1 used here
                    )
                end
                alpha0 ~ dnorm(0.0, 1.0E-6)
                alpha1 ~ dnorm(0.0, 1.0E-6)
                alpha2 ~ dnorm(0.0, 1.0E-6)
                alpha12 ~ dnorm(0.0, 1.0E-6)
                tau ~ dgamma(0.001, 0.001)
                sigma = 1 / sqrt(tau)
            end
            #! format: on
        end
    end

    # Test optional type annotations
    @testset "Optional type annotations" begin
        #! format: off
        @model function seeds_optional_types(
            (; r::of(Array, Int, 21),  # Full type annotation
               b,                       # No type annotation - inferred
               alpha0::of(Real),        # Type annotation without bounds
               alpha1,                  # No type annotation
               alpha2::of(Real),
               alpha12,                 # No type annotation
               tau::of(Real, 0, nothing)  # Type annotation with bounds
            ), 
            x1, x2, N, n
        )
            for i in 1:N
                r[i] ~ dbin(p[i], n[i])
                b[i] ~ dnorm(0.0, tau)
                p[i] = logistic(
                    alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
                )
            end
            alpha0 ~ dnorm(0.0, 1.0E-6)
            alpha1 ~ dnorm(0.0, 1.0E-6)
            alpha2 ~ dnorm(0.0, 1.0E-6)
            alpha12 ~ dnorm(0.0, 1.0E-6)
            tau ~ dgamma(0.001, 0.001)
            sigma = 1 / sqrt(tau)
        end
        #! format: on

        data = JuliaBUGS.BUGSExamples.seeds.data

        # Test with empty observations
        m1 = seeds_optional_types((;), data.x1, data.x2, data.N, data.n)
        @test m1 isa JuliaBUGS.BUGSModel

        # Test with partial observations
        m2 = seeds_optional_types((r=data.r,), data.x1, data.x2, data.N, data.n)
        @test m2 isa JuliaBUGS.BUGSModel
    end

    # Test of type validation
    @testset "Of type validation" begin
        # Model with type constraints
        @model function validated_model(
            (;
                x::of(Array, Int, 3),    # Must be Int array of size 3
                y::of(Real, 0, nothing),   # Must be non-negative Real
            ), n
        )
            for i in 1:n
                x[i] ~ dnorm(0, 1)
            end
            y ~ dgamma(1, 1)
        end

        # Test with valid data
        model1 = validated_model((x=[1, 2, 3], y=1.5), 3)
        @test model1 isa JuliaBUGS.BUGSModel

        # Test that validation happens for observed data
        # This should fail because x has wrong size (currently fails during compilation with BoundsError)
        @test_throws BoundsError validated_model((x=[1, 2], y=1.5), 3)

        # This should fail because y is negative
        @test_throws ErrorException validated_model((x=[1, 2, 3], y=-1.5), 3)
    end
end
