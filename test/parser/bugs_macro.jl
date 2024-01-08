# Only possible modify `@bugs` macro makes to the expressions
@test (@bugs begin
    a ~ f(x[])
end) == MacroTools.@q begin
    a ~ f(x[:])
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
    @test (@bugs (x[1] = 1; y[1] ~ dnorm(0, 1))) == MacroTools.@q begin
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
