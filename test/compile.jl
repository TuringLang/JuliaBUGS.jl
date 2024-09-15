@testset "compile corner cases" begin
    @testset "test variables exist on the left hand side of the both kinds of assignment" begin
        @testset "not transformed variable, so error"
        ex = @bugs begin
            a ~ Normal(0, 1)
            b = a
            b ~ Normal(0, 1)
        end
        @test_throws ErrorException compile(ex, (;), (;))

        @testset "transformed variable, so no error" begin
            ex = @bugs begin
                a ~ Normal(0, 1)
                b = a
                b ~ Normal(0, 1)
            end
            compile(ex, (; a=1), (;))
        end
    end

    @testset "assign array variable to another array variable" begin
        model = compile((@bugs begin
            b[1:2] ~ dmnorm(μ[:], σ[:, :])
            a[1:2] = b[:]
        end), (; μ=[0, 1], σ=[1 0; 0 1]), (;))
    end
end

@testset "error messages on undeclared variables" begin
    @testset "same variable names refer to both scalar and array" begin
        model_def = @bugs begin
            x[1] ~ dnorm(0, 1)
            y ~ dnorm(x, 1)
        end
        @test_throws ErrorException compile(model_def, (;))
    end

    @testset "undeclared scalar variable" begin
        model_def = @bugs begin
            x[1] ~ dnorm(0, 1)
            y ~ dnorm(x[1], z)
        end
        @test_throws ErrorException compile(model_def, (;))
    end
    
    @testset "undeclared array variable" begin
        model_def = @bugs begin
            x[1] ~ dnorm(0, 1)
            y ~ dnorm(x[1], x[2])
        end
        @test_throws ErrorException compile(model_def, (;))
    end
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
