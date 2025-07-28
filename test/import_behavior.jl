using Test
using JuliaBUGS

@testset "Import Behavior Tests" begin
    @testset "@bugs macro uses restricted module" begin
        # Test 1: @bugs has access to BUGS primitives without imports
        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = exp(x)
            z ~ dgamma(1, 1)
        end
        model = compile(bugs_expr, NamedTuple())
        @test model isa JuliaBUGS.BUGSModel

        # Test 2: @bugs cannot access user-defined functions
        my_func(x) = x + 100
        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = my_func(x)  # This should fail at compile time
        end
        @test_throws UndefVarError compile(bugs_expr, NamedTuple())
    end

    @testset "@model macro uses caller's module" begin
        # Import what we need for @model
        using JuliaBUGS.BUGSPrimitives: dnorm, dgamma

        # Define a custom function
        custom_transform(x) = x^2 + 1

        @model function test_model((; theta, y))
            theta ~ dnorm(0, 1)
            transformed = custom_transform(theta)  # Should work
            y ~ dgamma(transformed, 1)
        end

        model = test_model(NamedTuple())
        @test model isa JuliaBUGS.BUGSModel
    end
end
