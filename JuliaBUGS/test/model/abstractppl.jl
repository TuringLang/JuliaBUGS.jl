using Test
using JuliaBUGS
using JuliaBUGS.Model:
    condition,
    decondition,
    parameters,
    set_evaluation_mode,
    UseGeneratedLogDensityFunction,
    UseGraph
using LogDensityProblems
using AbstractPPL: @varname

JuliaBUGS.@bugs_primitive Normal Gamma

@testset "AbstractPPL interface" begin
    @testset "condition" begin
        @testset "Generated function regeneration" begin
            # Test that conditioned models generate their own log density functions
            model_def = @bugs begin
                x ~ Normal(0, 1)
                y ~ Normal(x, 1)
                z ~ Normal(y, 1)
            end

            model = compile(model_def, (; z=2.5))
            model_cond = condition(model, (; x=1.0))

            # Check that they have different generated functions
            @test model.log_density_computation_function !==
                model_cond.log_density_computation_function
            @test !isnothing(model_cond.log_density_computation_function)

            # Test that the generated function works correctly
            model_cond_gen = set_evaluation_mode(
                model_cond, UseGeneratedLogDensityFunction()
            )
            params = [0.5]  # Only y is a parameter now
            logp1 = LogDensityProblems.logdensity(model_cond_gen, params)

            # Compare with graph evaluation
            model_cond_graph = set_evaluation_mode(model_cond, UseGraph())
            logp2 = LogDensityProblems.logdensity(model_cond_graph, params)

            @test logp1 ≈ logp2
        end

        @testset "Array model conditioning with correct parameter ordering" begin
            # This was the main bug - parameter ordering mismatch
            model_def = @bugs begin
                for i in 1:3
                    x[i] ~ Normal(0, 1)
                end
                for i in 1:3
                    y[i] ~ Normal(x[i], 1)
                end
            end

            model = compile(model_def, (;))
            model_cond = condition(
                model, Dict(@varname(x[1]) => 0.5, @varname(x[3]) => 1.5)
            )

            # Check that generated functions are different
            @test model.log_density_computation_function !==
                model_cond.log_density_computation_function
            @test !isnothing(model_cond.log_density_computation_function)

            # Test with generated function
            model_cond_gen = set_evaluation_mode(
                model_cond, UseGeneratedLogDensityFunction()
            )
            # Parameters should be in order: [x[2], y[1], y[2], y[3]]
            params = [0.0, 1.0, 2.0, 3.0]
            logp1 = LogDensityProblems.logdensity(model_cond_gen, params)

            # Compare with graph evaluation
            model_cond_graph = set_evaluation_mode(model_cond, UseGraph())
            logp2 = LogDensityProblems.logdensity(model_cond_graph, params)

            @test logp1 ≈ logp2

            # Verify parameter ordering
            @test parameters(model_cond) ==
                [@varname(x[2]), @varname(y[1]), @varname(y[2]), @varname(y[3])]
        end

        @testset "Multiple conditioning steps" begin
            model_def = @bugs begin
                a ~ Normal(0, 1)
                b ~ Normal(a, 1)
                c ~ Normal(b, 1)
                d ~ Normal(c, 1)
            end

            model = compile(model_def, (; d=3.0))

            # First conditioning
            model_cond1 = condition(model, (; a=0.5))
            @test model.log_density_computation_function !==
                model_cond1.log_density_computation_function

            # Second conditioning
            model_cond2 = condition(model_cond1, (; b=1.0))
            @test model_cond1.log_density_computation_function !==
                model_cond2.log_density_computation_function
            @test model.log_density_computation_function !==
                model_cond2.log_density_computation_function

            # All functions should be different and non-null
            @test !isnothing(model.log_density_computation_function)
            @test !isnothing(model_cond1.log_density_computation_function)
            @test !isnothing(model_cond2.log_density_computation_function)

            # Test evaluation
            model_cond2_gen = set_evaluation_mode(
                model_cond2, UseGeneratedLogDensityFunction()
            )
            params = [1.5]  # Only c is a parameter
            logp = LogDensityProblems.logdensity(model_cond2_gen, params)
            @test isfinite(logp)
        end

        @testset "Conditioning with subsumption" begin
            model_def = @bugs begin
                for i in 1:3
                    x[i] ~ Normal(0, 1)
                end
                y ~ Normal(sum(x[:]), 1)
            end

            model = compile(model_def, (; y=2.0))

            # Condition on entire array using subsumption (should warn)
            model_cond = @test_logs(
                (
                    :warn,
                    "Variable x does not exist in the model. Conditioning on subsumed variables instead: x[1], x[2], x[3]",
                ),
                condition(model, Dict(@varname(x) => [1.0, 2.0, 3.0]))
            )

            @test !isnothing(model_cond.log_density_computation_function)
            @test length(parameters(model_cond)) == 0  # No parameters left

            # Can still evaluate log density
            model_cond_gen = set_evaluation_mode(
                model_cond, UseGeneratedLogDensityFunction()
            )
            logp = LogDensityProblems.logdensity(model_cond_gen, Float64[])
            @test isfinite(logp)
        end
    end

    @testset "decondition" begin
        @testset "Basic deconditioning" begin
            model_def = @bugs begin
                x ~ Normal(0, 1)
                y ~ Normal(x, 1)
                z ~ Normal(y, 1)
            end

            model = compile(model_def, (; z=2.5))
            model_cond = condition(model, (; x=1.0, y=1.5))
            model_decond = decondition(model_cond, [@varname(y)])

            # All should have different generated functions
            @test model.log_density_computation_function !==
                model_cond.log_density_computation_function
            @test model_cond.log_density_computation_function !==
                model_decond.log_density_computation_function
            @test !isnothing(model_decond.log_density_computation_function)

            # Test evaluation
            model_decond_gen = set_evaluation_mode(
                model_decond, UseGeneratedLogDensityFunction()
            )
            params = [2.0]  # Only y is a parameter
            logp = LogDensityProblems.logdensity(model_decond_gen, params)
            @test isfinite(logp)

            # Compare with graph evaluation
            model_decond_graph = set_evaluation_mode(model_decond, UseGraph())
            logp2 = LogDensityProblems.logdensity(model_decond_graph, params)
            @test logp ≈ logp2
        end

        @testset "Full deconditioning to base model" begin
            model_def = @bugs begin
                a ~ Normal(0, 1)
                b ~ Normal(a, 1)
                c ~ Normal(b, 1)
            end

            model = compile(model_def, (; c=2.0))

            # Multiple conditioning steps
            model_cond1 = condition(model, (; a=0.5))
            model_cond2 = condition(model_cond1, (; b=1.0))

            # Full decondition
            model_restored = decondition(model_cond2)

            # Should have different generated function from conditioned models
            @test model_cond2.log_density_computation_function !==
                model_restored.log_density_computation_function
            @test !isnothing(model_restored.log_density_computation_function)

            # Should have same parameters as original
            @test parameters(model_restored) == parameters(model)

            # Test evaluation
            model_restored_gen = set_evaluation_mode(
                model_restored, UseGeneratedLogDensityFunction()
            )
            params = [0.5, 1.0]  # a and b
            logp = LogDensityProblems.logdensity(model_restored_gen, params)
            @test isfinite(logp)
        end

        @testset "Error handling" begin
            model_def = @bugs begin
                x ~ Normal(0, 1)
                y ~ Normal(x, 1)
            end

            model = compile(model_def, (; y=1.0))

            # Cannot decondition without base_model
            @test_throws ArgumentError(
                "This is a unconditioned model. Use decondition(model, vars) to specify variables to decondition.",
            ) decondition(model)

            # Cannot decondition originally observed data
            model_cond = condition(model, (; x=0.5))
            @test_throws ArgumentError(
                "Cannot decondition y: it was observed in the original data"
            ) decondition(model_cond, [@varname(y)])
        end
    end

    @testset "Conditioned model log density computation" begin
        # Test that conditioned models compute log joint correctly
        model_def = @bugs begin
            mu ~ Normal(0, 10)
            sigma ~ Gamma(1, 1)
            x ~ Normal(mu, sigma)
            y ~ Normal(mu, sigma)
        end

        model = compile(model_def, (; x=1.0, y=2.0))
        model_cond = condition(model, (; mu=0.5))

        # This model should successfully generate a new function
        @test !isnothing(model.log_density_computation_function)
        @test !isnothing(model_cond.log_density_computation_function)
        @test model.log_density_computation_function !==
            model_cond.log_density_computation_function

        # Test evaluation
        model_cond_gen = set_evaluation_mode(model_cond, UseGeneratedLogDensityFunction())
        params = [2.0]  # Only sigma
        logp1 = LogDensityProblems.logdensity(model_cond_gen, params)

        model_cond_graph = set_evaluation_mode(model_cond, UseGraph())
        logp2 = LogDensityProblems.logdensity(model_cond_graph, params)

        @test logp1 ≈ logp2
    end
end
