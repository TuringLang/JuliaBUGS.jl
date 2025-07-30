using Test
using JuliaBUGS
using JuliaBUGS: @bugs_primitive

@testset "Import Behavior Tests" begin
    @testset "@bugs macro uses restricted module" begin
        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = exp(x)
            z ~ dgamma(1, 1)
        end
        model = compile(bugs_expr, NamedTuple())
        @test model isa JuliaBUGS.BUGSModel

        my_func(x) = x + 100
        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = my_func(x)
        end
        @test_throws ErrorException compile(bugs_expr, NamedTuple())

        @bugs_primitive my_func
        model2 = compile(bugs_expr, NamedTuple())
        @test model2 isa JuliaBUGS.BUGSModel

        bugs_expr = @bugs begin
            a ~ dnorm(0, 1)
            b = log(abs(a))
            c = pow(a, 2)
            d = sin(a) + cos(a)
            e = logit(0.5)
            f = phi(a)
        end
        model = compile(bugs_expr, NamedTuple())
        @test model isa JuliaBUGS.BUGSModel
    end

    @testset "@model macro uses caller's module" begin
        using JuliaBUGS.BUGSPrimitives: dnorm, dgamma

        # Define function in Main module (where tests run)
        Main.eval(:(custom_transform_for_test(x) = x^2 + 1))

        @model function test_model((; theta, y))
            theta ~ dnorm(0, 1)
            transformed = Main.custom_transform_for_test(theta)
            y ~ dgamma(transformed, 1)
        end

        model = test_model(NamedTuple())
        @test model isa JuliaBUGS.BUGSModel
    end

    @testset "@bugs_primitive registration" begin
        special_func(x) = x * 3
        @bugs_primitive special_func

        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = special_func(x)
        end
        model = compile(bugs_expr, NamedTuple())
        @test model isa JuliaBUGS.BUGSModel

        @test isdefined(JuliaBUGS, :special_func)
        @test JuliaBUGS.special_func(5) == 15
    end

    @testset "@bugs_primitive with multiple functions" begin
        func1(x) = x + 10
        func2(x, y) = x * y
        func3(x) = sqrt(abs(x))

        @bugs_primitive func1 func2 func3

        bugs_expr = @bugs begin
            a ~ dnorm(0, 1)
            b = func1(a)
            c = func2(a, b)
            d = func3(c)
        end
        model = compile(bugs_expr, NamedTuple())
        @test model isa JuliaBUGS.BUGSModel
    end

    @testset "Unregistered functions in @bugs" begin
        # Test that unregistered functions throw errors during validation
        unregistered_func(x) = x * 5

        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = unregistered_func(x)
        end
        @test_throws ErrorException compile(bugs_expr, NamedTuple())

        # Test that error message contains expected guidance
        try
            compile(bugs_expr, NamedTuple())
        catch e
            @test occursin("not allowed in @bugs", e.msg)
            @test occursin("@bugs_primitive", e.msg)
        end

        # Test that Base functions like Base.exp work since exp is in allowlist
        bugs_expr2 = @bugs begin
            x ~ dnorm(0, 1)
            y = exp(x)  # This should work because exp is in the allowlist
        end
        model = compile(bugs_expr2, NamedTuple())
        @test model isa JuliaBUGS.BUGSModel
    end

    @testset "Qualified names in @bugs" begin
        # Test that qualified names are rejected in @bugs
        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = Base.exp(x)
        end
        @test_throws ErrorException compile(bugs_expr, NamedTuple())

        try
            compile(bugs_expr, NamedTuple())
        catch e
            @test occursin("Qualified function names are not supported in @bugs", e.msg)
            @test occursin("Base.exp", e.msg)
        end
    end

    @testset "Qualified names in @model" begin
        using JuliaBUGS.BUGSPrimitives: dnorm

        # Define a custom function at module level for testing
        @eval Main module TestModuleForJuliaBUGS
        custom_func(x) = x * 2 + 5
        end

        # Test that @model macro accepts qualified names
        @model function model_with_qualified((; x, y))
            x ~ dnorm(0, 1)
            y = Main.TestModuleForJuliaBUGS.custom_func(x)
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
end
