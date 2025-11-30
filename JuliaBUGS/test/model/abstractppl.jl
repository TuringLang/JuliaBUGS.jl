using Test
using JuliaBUGS
using JuliaBUGS.Model:
    condition,
    decondition,
    parameters,
    set_evaluation_mode,
    set_observed_values!,
    regenerate_log_density_function,
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
            logp1 = Base.invokelatest(LogDensityProblems.logdensity, model_cond_gen, params)

            # Compare with graph evaluation
            model_cond_graph = set_evaluation_mode(model_cond, UseGraph())
            logp2 = Base.invokelatest(
                LogDensityProblems.logdensity, model_cond_graph, params
            )

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
            logp1 = Base.invokelatest(LogDensityProblems.logdensity, model_cond_gen, params)

            # Compare with graph evaluation
            model_cond_graph = set_evaluation_mode(model_cond, UseGraph())
            logp2 = Base.invokelatest(
                LogDensityProblems.logdensity, model_cond_graph, params
            )

            @test logp1 ≈ logp2

            # Verify parameter ordering (note: order may differ from original due to
            # statement reordering in source generation, but set should be correct)
            @test Set(parameters(model_cond)) ==
                Set([@varname(x[2]), @varname(y[1]), @varname(y[2]), @varname(y[3])])
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
            logp = Base.invokelatest(LogDensityProblems.logdensity, model_cond2_gen, params)
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
            logp = Base.invokelatest(
                LogDensityProblems.logdensity, model_cond_gen, Float64[]
            )
            @test isfinite(logp)
        end

        @testset "Fast conditioning path and observed value updates" begin
            @testset "Fast conditioning skips regeneration and forces graph mode" begin
                model_def = @bugs begin
                    x ~ Normal(0, 1)
                    y ~ Normal(x, 1)
                end

                model = compile(model_def, (;))

                # Regular conditioning (default regenerates)
                model_reg = condition(model, Dict(@varname(x) => 1.0))
                @test !isnothing(model_reg.log_density_computation_function)

                # Fast conditioning (no regeneration)
                model_fast = condition(
                    model, Dict(@varname(x) => 1.0); regenerate_log_density=false
                )
                @test model_fast.log_density_computation_function === nothing
                @test model_fast.evaluation_mode isa UseGraph

                # Same parameters
                @test parameters(model_reg) == parameters(model_fast)

                # Compare log density via graph evaluation
                params = zeros(length(parameters(model_fast)))
                logp_fast = Base.invokelatest(
                    LogDensityProblems.logdensity,
                    set_evaluation_mode(model_fast, UseGraph()),
                    params,
                )
                logp_reg = Base.invokelatest(
                    LogDensityProblems.logdensity,
                    set_evaluation_mode(model_reg, UseGraph()),
                    params,
                )
                @test logp_fast ≈ logp_reg
            end

            @testset "set_observed_values! updates values and validates" begin
                # Model with a deterministic node to hit validation
                model_def = @bugs begin
                    x ~ Normal(0, 1)
                    y = x^2              # deterministic
                    z ~ Normal(y, 1)
                end

                model = compile(model_def, (; z=2.0))

                # Fast condition on x
                m = condition(model, Dict(@varname(x) => 1.0); regenerate_log_density=false)
                @test m.evaluation_mode isa UseGraph

                # Update observed x value without reconditioning
                m2 = set_observed_values!(m, Dict(@varname(x) => 2.0))
                @test m2.evaluation_env.x == 2.0

                # Structure unchanged (x observed; only z observed from data; no parameters)
                # Here parameters is empty because y is deterministic and z is observed
                @test parameters(m2) == parameters(m)

                # Errors on invalid updates
                @test_throws ArgumentError set_observed_values!(
                    m2, Dict(@varname(y) => 3.0)
                )  # deterministic

                # Updating originally observed data should be allowed
                m3 = set_observed_values!(m2, Dict(@varname(z) => 1.0))
                @test m3.evaluation_env.z == 1.0
                # To test non-observed error, try updating a parameter in a different model.
            end

            @testset "set_observed_values! errors on non-observed variables" begin
                model_def = @bugs begin
                    x ~ Normal(0, 1)
                    y ~ Normal(x, 1)
                end
                model = compile(model_def, (;))
                m = condition(model, Dict(@varname(x) => 1.0); regenerate_log_density=false)
                # y is not observed
                @test_throws ArgumentError set_observed_values!(m, Dict(@varname(y) => 0.0))
            end

            @testset "Regeneration after fast conditioning (no mode change)" begin
                model_def = @bugs begin
                    x ~ Normal(0, 1)
                    y ~ Normal(x, 1)
                end

                model = compile(model_def, (;))
                m = condition(model, Dict(@varname(x) => 1.0); regenerate_log_density=false)
                @test m.log_density_computation_function === nothing

                # Regenerate compiled function without changing mode
                m2 = regenerate_log_density_function(m)
                @test !isnothing(m2.log_density_computation_function)
                @test m2.evaluation_mode isa UseGraph

                # Can switch to generated mode explicitly and match graph
                params = zeros(length(parameters(m2)))
                logp_gen = Base.invokelatest(
                    LogDensityProblems.logdensity,
                    set_evaluation_mode(m2, UseGeneratedLogDensityFunction()),
                    params,
                )
                logp_graph = Base.invokelatest(
                    LogDensityProblems.logdensity,
                    set_evaluation_mode(m2, UseGraph()),
                    params,
                )
                @test logp_gen ≈ logp_graph
            end
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
            logp = Base.invokelatest(
                LogDensityProblems.logdensity, model_decond_gen, params
            )
            @test isfinite(logp)

            # Compare with graph evaluation
            model_decond_graph = set_evaluation_mode(model_decond, UseGraph())
            logp2 = Base.invokelatest(
                LogDensityProblems.logdensity, model_decond_graph, params
            )
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
            logp = Base.invokelatest(
                LogDensityProblems.logdensity, model_restored_gen, params
            )
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
        logp1 = Base.invokelatest(LogDensityProblems.logdensity, model_cond_gen, params)

        model_cond_graph = set_evaluation_mode(model_cond, UseGraph())
        logp2 = Base.invokelatest(LogDensityProblems.logdensity, model_cond_graph, params)

        @test logp1 ≈ logp2
    end
end
