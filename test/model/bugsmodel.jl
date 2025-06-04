@testset "Compile Vol.1 BUGS Examples" begin
    @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
        m = JuliaBUGS.BUGSExamples.VOLUME_1[m]
        model = compile(m.model_def, m.data, m.inits)
    end
end

@testset "initialize!" begin
    @testset "rats" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats
        model = compile(model_def, data)
        model_init_1 = initialize!(model, inits)
        @test AbstractPPL.get(model_init_1.evaluation_env, @varname(alpha[1])) == 250
        @test AbstractPPL.get(model_init_1.evaluation_env, @varname(var"alpha.c")) == 150

        model_init_2 = initialize!(model, fill(0.1, 65))
        @test AbstractPPL.get(model_init_2.evaluation_env, @varname(alpha[1])) == 0.1
        @test AbstractPPL.get(model_init_2.evaluation_env, @varname(var"alpha.c")) == 0.1
    end

    @testset "pumps" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.pumps
        model = compile(model_def, data)
        model_init_1 = initialize!(model, inits)
        @test AbstractPPL.get(model_init_1.evaluation_env, @varname(alpha)) == 1
        @test AbstractPPL.get(model_init_1.evaluation_env, @varname(beta)) == 1
    end
end

@testset "dot call" begin
    model_def = @bugs begin
        x[1:2] ~ Distributions.product_distribution(fill(Distributions.Normal(0, 1), 2))
    end
    model = compile(model_def, (;))
    @test model.evaluation_env.x isa Vector{Float64}
end
