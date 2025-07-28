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
        @test_throws UndefVarError compile(bugs_expr, NamedTuple())

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

        custom_transform(x) = x^2 + 1

        @model function test_model((; theta, y))
            theta ~ dnorm(0, 1)
            transformed = custom_transform(theta)
            y ~ dgamma(transformed, 1)
        end

        model = test_model(NamedTuple())
        @test model isa JuliaBUGS.BUGSModel

        @test_throws UndefVarError @eval @model function fail_model((; x))
            x ~ dbeta(1, 1)
        end
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

    @testset "Module isolation prevents access to standard library" begin
        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = map(z -> z + 1, [x])
        end
        @test_throws UndefVarError compile(bugs_expr, NamedTuple())

        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            _ = println(x)
        end
        @test_throws UndefVarError compile(bugs_expr, NamedTuple())
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

    @testset "Qualified names in @bugs" begin
        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = SomeModule.some_func(x)
        end
        @test_throws UndefVarError compile(bugs_expr, NamedTuple())

        bugs_expr = @bugs begin
            x ~ dnorm(0, 1)
            y = Base.exp(x)
        end
        @test_throws UndefVarError compile(bugs_expr, NamedTuple())
    end
end
