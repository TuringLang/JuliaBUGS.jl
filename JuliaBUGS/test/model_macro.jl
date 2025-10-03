using JuliaBUGS
using JuliaBUGS: @model, @of

module TestPkg
using Distributions: Normal
test_dist(x, y) = Normal(x, y)
end

custom_transform_for_test(x) = x^2 + 1

@testset "model macro" begin
    @testset "Basic Model Usage" begin
        @testset "Minimal model body" begin
            #! format: off
            @model function minimal_model((; x))
                x ~ Normal(0, 1)
            end
            #! format: on

            model = minimal_model((;))
            @test model isa JuliaBUGS.BUGSModel
        end

        @testset "External type definition" begin
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

        @testset "Regular models without of-type validation" begin
            #! format: off
            @model function regular_model((; x, y))
                x ~ Normal(0, 1)
                y ~ Normal(x, 1)
            end
            #! format: on

            # This should work without any validation
            model = regular_model((x=0.5, y=0.5))
            @test model isa JuliaBUGS.BUGSModel

            # Even with "wrong" types, it should fail at compile time due to type checking
            @test_throws Exception regular_model((x="not a number", y=0.5))
        end
    end

    @testset "Of-Type Validation" begin
        # Define some of types for testing
        SimpleOfType = @of(x = of(Real), y = of(Real, 0, 1))
        ArrayOfType = @of(n = of(Int; constant=true), data = of(Array, n, 2))

        @testset "Valid evaluation_env passes validation" begin
            # Model with all required fields
            #! format: off
            @model function valid_model((; x, y)::SimpleOfType)
                x ~ Normal(0, 1)
                y ~ Beta(1, 1)
            end
            #! format: on

            # Providing initial values that satisfy constraints
            model = valid_model((x=0.0, y=0.5))
            @test model isa JuliaBUGS.BUGSModel
            @test haskey(model.evaluation_env, :x)
            @test haskey(model.evaluation_env, :y)
        end

        @testset "Initial parameter validation" begin
            BoundedType = @of(alpha = of(Real, 0, 1), beta = of(Real, 0, nothing))

            #! format: off
            @model function bounded_model((; alpha, beta)::BoundedType)
                alpha ~ Beta(2, 2)
                beta ~ Exponential(1)
            end
            #! format: on

            # Valid initial values
            model = bounded_model((alpha=0.5, beta=1.0))
            @test model isa JuliaBUGS.BUGSModel

            # Initial value outside bounds should fail
            @test_throws ErrorException bounded_model((alpha=1.5, beta=1.0))  # alpha > 1
            @test_throws ErrorException bounded_model((alpha=0.5, beta=-1.0))  # beta < 0

            # Wrong type should fail
            @test_throws ErrorException bounded_model((alpha="not a number", beta=1.0))
        end

        @testset "Array dimension validation" begin
            # Create concrete type with n=3 first
            ConcreteArrayType = of(ArrayOfType; n=3)

            # Model with correct array dimensions
            @model function array_model((; data)::ConcreteArrayType, n)
                for i in 1:n
                    for j in 1:2
                        data[i, j] ~ Normal(0, 1)
                    end
                end
            end

            # This should work with n=3
            model = array_model((data=zeros(3, 2),), 3)
            @test model isa JuliaBUGS.BUGSModel

            # Wrong dimensions should fail
            @test_throws ErrorException array_model((data=zeros(3, 3),), 3)  # wrong second dimension
            @test_throws BoundsError array_model((data=zeros(2, 2),), 3)  # wrong first dimension - BoundsError during compilation
        end

        @testset "Model with deterministic variables" begin
            # Test that computed values are also validated
            ComputedType = @of(
                theta = of(Real, 0, 1), logit_theta = of(Real), n = of(Int; constant=true)
            )

            @model function computed_model((; theta)::ComputedType, n)
                theta ~ Beta(1, 1)
                logit_theta = log(theta / (1 - theta))
            end

            # This should work - the model computes logit_theta
            model = computed_model((theta=0.5,), 10)
            @test model isa JuliaBUGS.BUGSModel
            @test haskey(model.evaluation_env, :theta)
            @test haskey(model.evaluation_env, :logit_theta)
            @test model.evaluation_env.logit_theta ≈ 0.0
        end
    end

    @testset "Error Handling" begin
        # Try leaving out a stochastic variable (tau is used but not declared)
        @test_throws ErrorException begin
            #! format: off
            @model function bad_seeds(
                (; r, b, alpha0, alpha1, alpha2, alpha12
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
                (; r, b, alpha0, alpha1, alpha2, alpha12, tau), 
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
        @testset "Inline type annotations rejection" begin
            @test_throws LoadError eval(
                quote
                    #! format: off
                    JuliaBUGS.@model function invalid_inline((; x::Int, y::Float64))
                        x ~ Normal(0, 1)
                        y ~ Normal(0, 1)
                    end
                    #! format: on
                end
            )

            @test_throws LoadError eval(
                quote
                    #! format: off
                    JuliaBUGS.@model function invalid_inline_of((; x::of(Real), y))
                        x ~ Normal(0, 1)
                        y ~ Normal(0, 1)
                    end
                    #! format: on
                end
            )
        end

        @testset "Regular Julia struct rejection" begin
            struct RegularStruct
                x::Float64
                y::Float64
            end

            #! format: off
            @model function with_regular_struct((; x, y)::RegularStruct)
                x ~ Normal(0, 1)
                y ~ Normal(0, 1)
            end
            #! format: on

            # Should throw error when trying to create model with non-of type
            @test_throws ErrorException with_regular_struct((x=1.0, y=2.0))
        end

        @testset "Invalid function signatures" begin
            @test_throws LoadError eval(
                quote
                    JuliaBUGS.@model function bad_signature(params, x, y)
                        # Should fail - first arg must be destructuring
                    end
                end
            )

            @test_throws ArgumentError eval(quote
                JuliaBUGS.@model function no_params()
                    # Should fail - needs at least params argument
                end
            end)

            @test_throws LoadError eval(
                quote
                    JuliaBUGS.@model function just_number(42, x)
                        # Should fail - first arg must be destructuring
                    end
                end
            )
        end
    end

    @testset "Function Arguments" begin
        @testset "Function argument patterns" begin
            # Default values without type annotations work
            @model function with_defaults((; x), n=10, sigma=1.0)
                for i in 1:n
                    x ~ Normal(0, sigma)
                end
            end

            model = with_defaults((;))
            @test model isa JuliaBUGS.BUGSModel

            # Test with overriding defaults
            model2 = with_defaults((;), 5, 2.0)
            @test model2 isa JuliaBUGS.BUGSModel

            # Type annotations work when argument is always provided
            @model function with_types((; x), n, sigma::Float64)
                for i in 1:n
                    x ~ Normal(0, sigma)
                end
            end

            model3 = with_types((;), 10, 1.0)
            @test model3 isa JuliaBUGS.BUGSModel

            # Test unsupported argument syntax
            @test_throws ErrorException eval(
                quote
                    #! format: off
                    JuliaBUGS.@model function bad_args((; x), ::Int)
                        x ~ Normal(0, 1)
                    end
                    #! format: on
                end
            )
        end
    end

    @testset "@model macro uses caller's module" begin
        using JuliaBUGS.BUGSPrimitives: dnorm, dgamma

        @model function test_model((; theta, y))
            theta ~ dnorm(0, 1)
            transformed = custom_transform_for_test(theta)
            y ~ dgamma(transformed, 1)
        end

        model = test_model(NamedTuple())
        @test model isa JuliaBUGS.BUGSModel
    end

    @testset "Qualified names in @model" begin
        # Test that @model macro accepts qualified names
        @model function model_with_qualified((; x))
            x ~ TestPkg.test_dist(0, 1)
        end

        model = model_with_qualified(NamedTuple())
        @test model isa JuliaBUGS.BUGSModel

        # Test with Base functions
        @model function model_with_base((; x, y))
            x ~ dnorm(0, 1)
            y = Base.exp(x)
        end

        model2 = model_with_base(NamedTuple())
        @test model2 isa JuliaBUGS.BUGSModel
    end

    @testset "Advanced Usage" begin
        @testset "unflatten usage" begin
            using JuliaBUGS: unflatten

            TestParams = @of(
                mu = of(Real), sigma = of(Real, 0, nothing), data = of(Array, 10)
            )

            # Test unflatten with missing
            params = unflatten(TestParams, missing)
            @test params isa NamedTuple
            @test ismissing(params.mu)
            @test ismissing(params.sigma)
            @test params.data isa Vector{Missing}
            @test length(params.data) == 10

            # Model using unflatten
            @model function unflatten_model((; mu, sigma, data)::TestParams)
                mu ~ Normal(0, 1)
                sigma ~ Exponential(1)
                for i in 1:10
                    data[i] ~ Normal(mu, sigma)
                end
            end

            model = unflatten_model(params)
            @test model isa JuliaBUGS.BUGSModel
        end
        @testset "Constant parameters in of types" begin
            ConstantTest = @of(
                n = of(Int; constant=true),
                m = of(Int; constant=true),
                data = of(Array, n, m),
                mu = of(Real)
            )

            # Use ConcreteType instead of ConstantTest to avoid symbolic dimension issues
            ConcreteType = of(ConstantTest; n=5, m=3)

            @model function const_model((; data, mu)::ConcreteType, n, m)
                mu ~ Normal(0, 1)
                for i in 1:n
                    for j in 1:m
                        data[i, j] ~ Normal(mu, 1)
                    end
                end
            end

            # Constants should be provided as function arguments
            model = const_model((data=zeros(5, 3), mu=0.0), 5, 3)
            @test model isa JuliaBUGS.BUGSModel
        end
        @testset "Parameter extraction from of type instances" begin
            SimpleType = @of(x = of(Real), y = of(Real, 0, 1))

            # Create an of type instance (not a NamedTuple)
            of_instance = of(SimpleType)

            #! format: off
            @model function of_type_model((; x, y)::SimpleType)
                x ~ Normal(0, 1)
                y ~ Beta(1, 1)
            end
            #! format: on

            # Should handle of type instances
            model = of_type_model(of_instance)
            @test model isa JuliaBUGS.BUGSModel
        end
    end
end
