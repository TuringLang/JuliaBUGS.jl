using JuliaBUGS: @bugs_primitive, compile
using JuliaBUGS.BUGSPrimitives: dgamma

@testset "bugs macro with Julia AST" begin
    @testset "Single index with empty brackets" begin
        @test (@bugs begin
            a ~ f(x[])
        end) == MacroTools.@q begin
            a ~ f(x[:])
        end
    end

    @testset "Implicit indexing on LHS" begin
        @test_throws ErrorException JuliaBUGS.Parser.bugs_top(
            :(
                begin
                    x[] ~ dmnorm(a[1:2], Σ[1:2, 1:2])
                end
            ), LineNumberNode(1)
        )
    end

    @testset "Indexing with expression" begin
        @bugs begin
            x[a[1] + 1, b] ~ dnorm(c[f(b[2])], 1)
        end
    end

    @testset "Indexing with ranges" begin
        @bugs begin
            x[a[1]:b[2], c[3]:d[4]] = f(a[1]:b[2], c[3]:d[4])
        end

        @bugs begin
            x[(f(a[1] + 1) + 1):b[2]] ~ dnorm(0, 1)
        end
    end

    @testset "Expressions on the RHS" begin
        @bugs begin
            a ~ dnorm(x[1] + 1, 1)
        end

        @bugs begin
            a ~ dnorm(f(x[a[1]], 1), 1)
        end

        @bugs begin
            a = f(g(x[a[1] + 1] + h(y, 2, x[1])))
        end
    end

    @testset "For loop" begin
        @bugs begin
            for i in 1:N
                Y[i] ~ dnorm(μ[i], τ)
                μ[i] = α + β * (x[i] - x̄)
            end
        end

        # expression as loop bound
        @bugs for i in 1:(N + 1)
            x[i] ~ dnorm(0, 1)
        end

        # tensor as loop bound
        @bugs for i in 1:a[1]
            x[i] ~ dnorm(0, 1)
        end
    end

    @testset "Multiple statements on the same line" begin
        ex = @bugs (x[1]=1; y[1] ~ dnorm(0, 1))
        @test ex == MacroTools.@q begin
            x[1] = 1
            y[1] ~ dnorm(0, 1)
        end
    end

    @testset "Disallowed syntax" begin
        # link function
        @test_throws ErrorException JuliaBUGS.Parser.bugs_top(
            :(
                begin
                    log(x) = a + 1
                end
            ), LineNumberNode(1)
        )

        # link function in stochastic assignment
        @test_throws ErrorException JuliaBUGS.Parser.bugs_top(
            :(
                begin
                    log(x) ~ dnorm(0, 1)
                end
            ), LineNumberNode(1)
        )

        # nested indexing
        @test_throws ErrorException JuliaBUGS.Parser.bugs_top(
            :(x[1] = y[1][1]), LineNumberNode(1)
        )
    end
end

@testset "equality test between two bugs macro" begin
    @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
        example = JuliaBUGS.BUGSExamples.VOLUME_1[m]
        @test JuliaBUGS.Parser._bugs_string_input(example.original_syntax_program, false) ==
            example.model_def
    end
end

@testset "warn deviance, cumulative, and density" begin
    model_1 = MacroTools.@q begin
        a ~ dnorm(0, 1)
        b = density(a, 1)
    end

    @test_logs (
        :warn,
        """`cumulative` and `density` functions are not supported in JuliaBUGS (aligned with MultiBUGS). These functions will be treated as user-defined functions. 
 Users can use `cdf` and `pdf` function from `Distributions.jl` to achieve the same functionality.""",
    ) begin
        JuliaBUGS.Parser.warn_cumulative_density_deviance(model_1)
    end

    model_2 = MacroTools.@q begin
        a ~ dnorm(0, 1)
        b = cumulative(a, 1)
    end

    @test_logs (
        :warn,
        """`cumulative` and `density` functions are not supported in JuliaBUGS (aligned with MultiBUGS). These functions will be treated as user-defined functions. 
 Users can use `cdf` and `pdf` function from `Distributions.jl` to achieve the same functionality.""",
    ) begin
        JuliaBUGS.Parser.warn_cumulative_density_deviance(model_2)
    end

    model_3 = MacroTools.@q begin
        a ~ dnorm(0, 1)
        b = deviance(a, 1)
    end

    @test_logs (
        :warn,
        """`deviance` function is not supported in JuliaBUGS. It will be treated as a user-defined function.""",
    ) begin
        JuliaBUGS.Parser.warn_cumulative_density_deviance(model_3)
    end
end

@testset "@bugs_primitive Tests" begin
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
end

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
end
