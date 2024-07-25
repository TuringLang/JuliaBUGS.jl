@testset "compile corner cases" begin
    # test variables exist on the left hand side of the both kinds of assignment
    let ex = @bugs begin
            a ~ Normal(0, 1)
            b = a
            b ~ Normal(0, 1)
        end
        @test_throws ErrorException compile(ex, (;), (;))
    end

    let ex = @bugs begin
            a ~ Normal(0, 1)
            b = a
            b ~ Normal(0, 1)
        end
        compile(ex, (; a=1), (;))
    end

    # assign array variable to another array variable
    model = compile((@bugs begin
        b[1:2] ~ dmnorm(μ[:], σ[:, :])
        a[1:2] = b[:]
    end), (; μ=[0, 1], σ=[1 0; 0 1]), (;))
end

@testset "initialize!" begin
    @testset "rats" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats
        model = compile(model_def, data)
        model_init_1 = initialize!(model, inits)
        @test model_init_1.varinfo[@varname(alpha[1])] == 250
        @test model_init_1.varinfo[@varname(var"alpha.c")] == 150

        model_init_2 = initialize!(model, fill(0.1, 65))
        @test model_init_2.varinfo[@varname(alpha[1])] == 0.1
        @test model_init_2.varinfo[@varname(var"alpha.c")] == 0.1
    end

    @testset "pumps" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.pumps
        model = compile(model_def, data)
        model_init_1 = initialize!(model, inits)
        @test model_init_1.varinfo[@varname(alpha)] == 1
        @test model_init_1.varinfo[@varname(beta)] == 1
    end
end
