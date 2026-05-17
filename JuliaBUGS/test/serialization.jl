@testset "serialization" begin
    ex = JuliaBUGS.BUGSExamples.rats
    model_def = include(JuliaBUGS.BUGSExamples.path(ex, "model.jl"))
    model = compile(model_def, ex.data)
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

@testset "serialization with lazy generation" begin
    model_def = @bugs begin
        for i in 1:N
            y[i] ~ dnorm(mu, tau)
        end
        mu ~ dnorm(0, 0.001)
        tau ~ dgamma(0.1, 0.1)
    end

    data = (; N=5, y=[1.0, 2.0, 3.0, 4.0, 5.0])

    @testset "log density function is Nothing after compilation (lazy)" begin
        model = compile(model_def, data)

        # Log density function should be Nothing after compilation (lazy)
        @test typeof(model).parameters[7] === Nothing
        @test isnothing(model.log_density_computation_function)

        # Serialize and deserialize
        tmpfile = tempname()
        try
            serialize(tmpfile, model)
            model_restored = deserialize(tmpfile)

            # Verify type parameter F is STILL Nothing after deserialization
            @test typeof(model_restored).parameters[7] === Nothing
            @test isnothing(model_restored.log_density_computation_function)

            # Verify types match exactly
            @test typeof(model) == typeof(model_restored)

            # Verify model works correctly after deserialization (uses UseGraph mode)
            θ = JuliaBUGS.Model.getparams(model)
            logp_original = Base.invokelatest(LogDensityProblems.logdensity, model, θ)
            logp_restored = Base.invokelatest(
                LogDensityProblems.logdensity, model_restored, θ
            )
            @test logp_original ≈ logp_restored
        finally
            rm(tmpfile, force=true)
        end
    end

    @testset "UseGraph and UseGeneratedLogDensityFunction produce same results" begin
        model = compile(model_def, data)

        # Get log density with UseGraph (default)
        θ = JuliaBUGS.Model.getparams(model)
        logp_graph = Base.invokelatest(LogDensityProblems.logdensity, model, θ)

        # Switch to UseGeneratedLogDensityFunction (triggers lazy generation)
        model_gen = JuliaBUGS.Model.set_evaluation_mode(
            model, JuliaBUGS.Model.UseGeneratedLogDensityFunction()
        )

        # Verify log density function was generated
        @test !isnothing(model_gen.log_density_computation_function)

        # Get log density with generated function
        logp_gen = Base.invokelatest(LogDensityProblems.logdensity, model_gen, θ)

        @test logp_graph ≈ logp_gen
    end

    @testset "serialization with generated function (distributed-like scenario)" begin
        model = compile(model_def, data)
        model_gen = JuliaBUGS.Model.set_evaluation_mode(
            model, JuliaBUGS.Model.UseGeneratedLogDensityFunction()
        )

        # Verify it has a generated function (which would break serialization)
        @test !isnothing(model_gen.log_density_computation_function)

        tmpfile = tempname()
        try
            serialize(tmpfile, model_gen)
            model_restored = deserialize(tmpfile)

            # Verification
            @test model_restored.evaluation_mode isa
                JuliaBUGS.Model.UseGeneratedLogDensityFunction
            @test !isnothing(model_restored.log_density_computation_function)

            # The function should be different (re-generated)
            @test model_restored.log_density_computation_function !==
                model_gen.log_density_computation_function

            # Results should be consistent
            θ = JuliaBUGS.Model.getparams(model_gen)
            logp_original = Base.invokelatest(LogDensityProblems.logdensity, model_gen, θ)
            logp_restored = Base.invokelatest(
                LogDensityProblems.logdensity, model_restored, θ
            )
            @test logp_original ≈ logp_restored
        finally
            rm(tmpfile, force=true)
        end
    end
end
