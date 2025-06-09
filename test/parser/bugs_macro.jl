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
