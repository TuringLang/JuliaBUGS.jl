@testset "serialization" begin
    (; model_def, data) = JuliaBUGS.BUGSExamples.rats
    model = compile(model_def, data)
    serialize("m.jls", model)
    deserialized = deserialize("m.jls")
    rm("m.jls", force=true)
    @testset "test values are correctly restored" begin
        for vn in MetaGraphsNext.labels(model.g)
            @test isequal(
                get(model.evaluation_env, vn), get(deserialized.evaluation_env, vn)
            )
        end

        @test model.transformed == deserialized.transformed
        @test model.untransformed_param_length == deserialized.untransformed_param_length
        @test model.transformed_param_length == deserialized.transformed_param_length
        @test all(
            model.untransformed_var_lengths[k] == deserialized.untransformed_var_lengths[k]
            for k in keys(model.untransformed_var_lengths)
        )
        @test all(
            model.transformed_var_lengths[k] == deserialized.transformed_var_lengths[k] for
            k in keys(model.transformed_var_lengths)
        )
        @test Set(model.graph_evaluation_data.sorted_parameters) ==
            Set(deserialized.graph_evaluation_data.sorted_parameters)
        # skip testing g
        @test model.model_def == deserialized.model_def
    end
end
