@testset "cumulative" begin
    model_def = @bugs begin
        a ~ Normal(0, 1)
        b = cumulative(a, 2)

        c[1] ~ Normal(0, 1)
        d[1] = cumulative(c[1], 2)
    end

    data, inits = (;), (;)

    model = compile(model_def, data, inits)

    @test model.distributions.a == Normal(0, 1)
    @test model.distributions.c[1] == Normal(0, 1)

    @test model.varinfo[@varname(b)] == cdf(Normal(0, 1), 2)
    @test model.varinfo[@varname(d[1])] == cdf(Normal(0, 1), 2)
end

@testset "density" begin
    model_def = @bugs begin
        a ~ Normal(0, 1)
        b = density(a, 2)

        c[1] ~ Normal(0, 1)
        d[1] = density(c[1], 2)
    end

    data, inits = (;), (;)

    model = compile(model_def, data, inits)

    @test model.distributions.a == Normal(0, 1)
    @test model.distributions.c[1] == Normal(0, 1)

    @test model.varinfo[@varname(b)] == pdf(Normal(0, 1), 2)
    @test model.varinfo[@varname(d[1])] == pdf(Normal(0, 1), 2)
end
