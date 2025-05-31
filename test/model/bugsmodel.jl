@testset "Model Invariants" begin
    @testset "Volume 1 Examples" begin
        @testset "$example_name" for example_name in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            example = JuliaBUGS.BUGSExamples.VOLUME_1[example_name]
            model = compile(example.model_def, example.data, example.inits)
            @test check_invariants(model)
        end
    end

    @testset "Volume 2 Examples" begin
        @testset "$example_name" for example_name in keys(JuliaBUGS.BUGSExamples.VOLUME_2)
            example = JuliaBUGS.BUGSExamples.VOLUME_2[example_name]
            model = compile(example.model_def, example.data, example.inits)
            @test check_invariants(model)
        end
    end
end
