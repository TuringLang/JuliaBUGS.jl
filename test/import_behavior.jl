using Test
using JuliaBUGS

@testset "Import Behavior Tests" begin
    @testset "@model requires explicit imports" begin
        # Create a module to test without imports
        @eval module TestNoImport
        using Test
        using JuliaBUGS

        JuliaBUGS.@parameters struct TestParams1
            x
        end

        # This should fail because dnorm is not imported
        @test_throws UndefVarError begin
            model = JuliaBUGS.@model function test_no_import((; x)::TestParams1, mu)
                x ~ dnorm(mu, 1)
            end
            model(TestParams1(), 0.0)
        end
        end

        # Test with explicit import in a different module
        @eval module TestWithImport
        using Test
        using JuliaBUGS
        using JuliaBUGS.BUGSPrimitives: dnorm

        JuliaBUGS.@parameters struct TestParams2
            x
        end

        model = JuliaBUGS.@model function test_with_import((; x)::TestParams2, mu)
            x ~ dnorm(mu, 1)
        end

        m = model(TestParams2(), 0.0)
        @test m isa JuliaBUGS.BUGSModel
        end
    end

    @testset "Package.function syntax" begin
        @eval module TestPackageSyntax
        using Test
        using JuliaBUGS

        # Test without package import
        JuliaBUGS.@parameters struct TestParams3
            y
        end

        @test_throws UndefVarError begin
            model = JuliaBUGS.@model function test_no_pkg((; y)::TestParams3, sigma)
                y ~ SomePackage.some_dist(0, sigma)
            end
            model(TestParams3(), 1.0)
        end

        # Test with package imports
        using JuliaBUGS.BUGSPrimitives
        using Distributions

        JuliaBUGS.@parameters struct TestParams4
            a
            b
        end

        model = JuliaBUGS.@model function test_with_pkg((; a, b)::TestParams4, tau)
            a ~ BUGSPrimitives.dgamma(1, tau)
            b ~ Distributions.Normal(0, 1)
        end

        m = model(TestParams4(), 1.0)
        @test m isa JuliaBUGS.BUGSModel
        end
    end

    @testset "@bugs macro auto-imports (legacy)" begin
        # @bugs should work without any imports
        bugs_expr = JuliaBUGS.@bugs begin
            x ~ dnorm(0, 1)
            y ~ dgamma(1, 1)
            z ~ dbern(0.5)
        end

        @test bugs_expr isa Expr
        @test bugs_expr.head == :block
    end

    @testset "@bugs_primitive uses caller's module" begin
        # Create a module for testing
        @eval module TestPrimitiveModule
        using JuliaBUGS
        using Test

        # Define and register a function
        test_func1(x) = x + 100
        JuliaBUGS.@bugs_primitive test_func1

        # Test it works
        @test JuliaBUGS.test_func1(5) == 105

        # Test from a submodule
        module SubModule
            using JuliaBUGS
            using Test

            test_func2(x) = x + 200
            JuliaBUGS.@bugs_primitive test_func2

            @test JuliaBUGS.test_func2(5) == 205
        end

        # Test multiple functions
        func3(x) = x * 2
        func4(x) = x * 3
        JuliaBUGS.@bugs_primitive func3 func4

        @test JuliaBUGS.func3(5) == 10
        @test JuliaBUGS.func4(5) == 15
        end

        # Verify functions are accessible from outside
        @test JuliaBUGS.test_func1(10) == 110
        @test JuliaBUGS.test_func2(10) == 210
    end

    @testset "Mixed import styles" begin
        @eval module TestMixed
        using Test
        using JuliaBUGS
        using JuliaBUGS.BUGSPrimitives: dnorm
        using JuliaBUGS.BUGSPrimitives  # Need full module for qualified names
        using Distributions

        JuliaBUGS.@parameters struct TestParams6
            a
            b
            c
        end

        model = JuliaBUGS.@model function test_mixed((; a, b, c)::TestParams6, mu, sigma)
            a ~ dnorm(mu, 1)                    # Direct import
            b ~ BUGSPrimitives.dgamma(1, 1)     # Package.function
            c ~ Distributions.Normal(0, sigma)   # External package
        end

        m = model(TestParams6(), 0.0, 1.0)
        @test m isa JuliaBUGS.BUGSModel
        end
    end

    @testset "Nested module scoping" begin
        @eval module OuterModule
        using JuliaBUGS
        using JuliaBUGS.BUGSPrimitives: dnorm
        using Test

        module InnerModule
            using JuliaBUGS
            using JuliaBUGS.BUGSPrimitives: dgamma
            using Test

            JuliaBUGS.@parameters struct InnerParams
                x
            end

            # InnerModule can only use dgamma, not dnorm
            @test_throws UndefVarError begin
                model = JuliaBUGS.@model function inner_test1((; x)::InnerParams, mu)
                    x ~ dnorm(mu, 1)  # Not imported in InnerModule
                end
                model(InnerParams(), 0.0)
            end

            # But dgamma works
            model = JuliaBUGS.@model function inner_test2((; x)::InnerParams, tau)
                x ~ dgamma(1, tau)
            end
            m = model(InnerParams(), 1.0)
            @test m isa JuliaBUGS.BUGSModel
        end

        JuliaBUGS.@parameters struct OuterParams
            y
        end

        # OuterModule can use dnorm
        model = JuliaBUGS.@model function outer_test((; y)::OuterParams, mu)
            y ~ dnorm(mu, 1)
        end
        m = model(OuterParams(), 0.0)
        @test m isa JuliaBUGS.BUGSModel
        end
    end

    @testset "Error messages are clear" begin
        @eval module TestErrors
        using Test
        using JuliaBUGS

        JuliaBUGS.@parameters struct TestParams7
            x
        end

        err = try
            model = JuliaBUGS.@model function test_error((; x)::TestParams7, mu)
                x ~ undefined_func(mu, 1)
            end
            model(TestParams7(), 0.0)
            nothing
        catch e
            e
        end

        @test err isa UndefVarError
        @test err.var == :undefined_func
        end
    end
end
