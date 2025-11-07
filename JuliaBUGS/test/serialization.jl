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

@testset "serialization with skip_source_generation" begin
    model_def = @bugs begin
        for i in 1:N
            y[i] ~ dnorm(mu, tau)
        end
        mu ~ dnorm(0, 0.001)
        tau ~ dgamma(0.1, 0.1)
    end

    data = (; N=5, y=[1.0, 2.0, 3.0, 4.0, 5.0])

    @testset "type parameter F=Nothing when skip_source_generation=true" begin
        model_no_gen = compile(model_def, data; skip_source_generation=true)

        # Verify type parameter F is Nothing before serialization
        @test typeof(model_no_gen).parameters[7] === Nothing
        @test isnothing(model_no_gen.log_density_computation_function)

        # Serialize and deserialize
        tmpfile = tempname()
        try
            serialize(tmpfile, model_no_gen)
            model_restored = deserialize(tmpfile)

            # Verify type parameter F is STILL Nothing after deserialization
            @test typeof(model_restored).parameters[7] === Nothing
            @test isnothing(model_restored.log_density_computation_function)

            # Verify types match exactly
            @test typeof(model_no_gen) == typeof(model_restored)

            # Verify model works correctly after deserialization
            θ = JuliaBUGS.Model.getparams(model_no_gen)
            logp_original = Base.invokelatest(LogDensityProblems.logdensity, model_no_gen, θ)
            logp_restored = Base.invokelatest(
                LogDensityProblems.logdensity, model_restored, θ
            )
            @test logp_original ≈ logp_restored
        finally
            rm(tmpfile, force=true)
        end
    end

    @testset "correctness comparison with default compilation" begin
        model_with_gen = compile(model_def, data)
        model_no_gen = compile(model_def, data; skip_source_generation=true)

        # Both should produce same results
        θ = JuliaBUGS.Model.getparams(model_with_gen)
        logp_with = Base.invokelatest(LogDensityProblems.logdensity, model_with_gen, θ)
        logp_without = Base.invokelatest(LogDensityProblems.logdensity, model_no_gen, θ)

        @test logp_with ≈ logp_without
    end
end
