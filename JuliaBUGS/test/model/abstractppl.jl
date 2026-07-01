using Test
using JuliaBUGS
using JuliaBUGS.Model:
    condition,
    decondition,
    fixed_parameters,
    generated_quantities,
    model_parameters,
    parameters,
    set_evaluation_mode,
    set_observed_values!,
    variable_type,
    FixedParameter,
    GeneratedQuantity,
    ModelParameter,
    Observation,
    regenerate_log_density_function,
    UseAutoMarginalization,
    UseGeneratedLogDensityFunction,
    UseGraph
using LogDensityProblems
using AbstractPPL: @varname, fix, unfix
using Distributions: Bernoulli, Gamma, Normal, logpdf

JuliaBUGS.@bugs_primitive Normal Gamma Bernoulli

@testset "AbstractPPL interface" begin
    @testset "condition" begin
        @testset "Generated function regeneration" begin
            # Test that conditioned models can generate log density functions lazily
            model_def = @bugs begin
                x ~ Normal(0, 1)
                y ~ Normal(x, 1)
                z ~ Normal(y, 1)
            end

            model = compile(model_def, (; z=2.5))
            model_cond = condition(model, (; x=1.0))

            # With lazy generation, log_density_computation_function is Nothing initially
            @test isnothing(model.log_density_computation_function)
            @test isnothing(model_cond.log_density_computation_function)

            # Test that the generated function works correctly after lazy generation
            model_cond_gen = set_evaluation_mode(
                model_cond, UseGeneratedLogDensityFunction()
            )
            # Now it should be generated
            @test !isnothing(model_cond_gen.log_density_computation_function)

            params = [0.5]  # Only y is a parameter now
            logp1 = Base.invokelatest(LogDensityProblems.logdensity, model_cond_gen, params)

            # Compare with graph evaluation
            model_cond_graph = set_evaluation_mode(model_cond, UseGraph())
            logp2 = Base.invokelatest(
                LogDensityProblems.logdensity, model_cond_graph, params
            )

            @test logp1 ≈ logp2
        end

        @testset "conditioning generated quantity updates ancestor classification" begin
            model_def = @bugs begin
                theta ~ Normal(0, 1)
                z ~ Normal(theta, 1)
                y ~ Normal(0, 1)
            end

            model = compile(model_def, (; y=0.0))
            @test isempty(model_parameters(model))
            @test @varname(theta) in generated_quantities(model)
            @test @varname(z) in generated_quantities(model)

            conditioned_model = condition(model, Dict(@varname(z) => 0.5))
            @test variable_type(conditioned_model, @varname(z)) == Observation
            @test variable_type(conditioned_model, @varname(theta)) == ModelParameter
            @test model_parameters(conditioned_model) == [@varname(theta)]
            @test @varname(theta) ∉ generated_quantities(conditioned_model)
            @test LogDensityProblems.dimension(conditioned_model) == 1

            params = [0.25]
            graph_logdensity = Base.invokelatest(
                LogDensityProblems.logdensity, conditioned_model, params
            )
            generated_conditioned_model = set_evaluation_mode(
                conditioned_model, UseGeneratedLogDensityFunction()
            )
            generated_logdensity = Base.invokelatest(
                LogDensityProblems.logdensity, generated_conditioned_model, params
            )
            @test generated_logdensity ≈ graph_logdensity
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

            # With lazy generation, functions are Nothing initially
            @test isnothing(model.log_density_computation_function)
            @test isnothing(model_cond.log_density_computation_function)

            # Verify parameter set (order may differ between graph and generated modes)
            @test Set(parameters(model_cond)) ==
                Set([@varname(x[2]), @varname(y[1]), @varname(y[2]), @varname(y[3])])

            # Test with generated function (triggers lazy generation)
            model_cond_gen = set_evaluation_mode(
                model_cond, UseGeneratedLogDensityFunction()
            )
            @test !isnothing(model_cond_gen.log_density_computation_function)

            # Use zeros to avoid parameter order issues
            params = zeros(LogDensityProblems.dimension(model_cond))
            logp1 = Base.invokelatest(LogDensityProblems.logdensity, model_cond_gen, params)

            # Compare with graph evaluation on the SAME model (model_cond_gen)
            model_cond_graph = set_evaluation_mode(model_cond_gen, UseGraph())
            logp2 = Base.invokelatest(
                LogDensityProblems.logdensity, model_cond_graph, params
            )

            @test logp1 ≈ logp2
        end

        @testset "Multiple conditioning steps" begin
            model_def = @bugs begin
                a ~ Normal(0, 1)
                b ~ Normal(a, 1)
                c ~ Normal(b, 1)
                d ~ Normal(c, 1)
            end

            model = compile(model_def, (; d=3.0))

            # With lazy generation, all models start with no pregenerated function
            @test isnothing(model.log_density_computation_function)

            # First conditioning
            model_cond1 = condition(model, (; a=0.5))
            @test isnothing(model_cond1.log_density_computation_function)

            # Second conditioning
            model_cond2 = condition(model_cond1, (; b=1.0))
            @test isnothing(model_cond2.log_density_computation_function)

            # Test evaluation with generated function
            model_cond2_gen = set_evaluation_mode(
                model_cond2, UseGeneratedLogDensityFunction()
            )
            @test !isnothing(model_cond2_gen.log_density_computation_function)

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

            # With lazy generation, log density function is not pregenerated
            @test isnothing(model_cond.log_density_computation_function)
            @test length(parameters(model_cond)) == 0  # No parameters left

            # Can still evaluate log density with generated function
            model_cond_gen = set_evaluation_mode(
                model_cond, UseGeneratedLogDensityFunction()
            )
            @test !isnothing(model_cond_gen.log_density_computation_function)
            logp = Base.invokelatest(
                LogDensityProblems.logdensity, model_cond_gen, Float64[]
            )
            @test isfinite(logp)
        end

        @testset "Fast conditioning path and observed value updates" begin
            @testset "set_observed_values! updates values and validates" begin
                # Model with a deterministic node to hit validation
                model_def = @bugs begin
                    x ~ Normal(0, 1)
                    y = x^2              # deterministic
                    z ~ Normal(y, 1)
                end

                model = compile(model_def, (; z=2.0))

                # Condition on x (lazy generation - no pregenerated log density function)
                m = condition(model, Dict(@varname(x) => 1.0))
                @test m.evaluation_mode isa UseGraph
                @test m.log_density_computation_function === nothing

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
                m = condition(model, Dict(@varname(x) => 1.0))
                # y is not observed
                @test_throws ArgumentError set_observed_values!(m, Dict(@varname(y) => 0.0))
            end

            @testset "Regeneration after conditioning (no mode change)" begin
                model_def = @bugs begin
                    x ~ Normal(0, 1)
                    y ~ Normal(x, 1)
                end

                model = compile(model_def, (;))
                m = condition(model, Dict(@varname(x) => 1.0))
                @test m.log_density_computation_function === nothing

                # Regenerate compiled function without changing mode
                m2 = regenerate_log_density_function(m)
                @test !isnothing(m2.log_density_computation_function)
                @test m2.evaluation_mode isa UseGraph

                # Can switch to generated mode explicitly and match graph
                params = zeros(LogDensityProblems.dimension(m2))
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

            # With lazy generation, all models start without pregenerated functions
            @test isnothing(model.log_density_computation_function)
            @test isnothing(model_cond.log_density_computation_function)
            @test isnothing(model_decond.log_density_computation_function)

            # Test evaluation with generated function
            model_decond_gen = set_evaluation_mode(
                model_decond, UseGeneratedLogDensityFunction()
            )
            @test !isnothing(model_decond_gen.log_density_computation_function)

            params = [2.0]  # Only y is a parameter
            logp = Base.invokelatest(
                LogDensityProblems.logdensity, model_decond_gen, params
            )
            @test isfinite(logp)

            # Compare with graph evaluation
            model_decond_graph = set_evaluation_mode(model_decond_gen, UseGraph())
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

            # With lazy generation, functions are not pregenerated
            @test isnothing(model_cond2.log_density_computation_function)
            @test isnothing(model_restored.log_density_computation_function)

            # Should have same parameters as original
            @test parameters(model_restored) == parameters(model)

            # Test evaluation with generated function
            model_restored_gen = set_evaluation_mode(
                model_restored, UseGeneratedLogDensityFunction()
            )
            @test !isnothing(model_restored_gen.log_density_computation_function)

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

    @testset "fix" begin
        @testset "fix is an intervention, not conditioning" begin
            model_def = @bugs begin
                theta ~ Normal(0, 1)
                x ~ Normal(theta, 1)
                y ~ Normal(x, 1)
            end

            model = compile(model_def, (; y=2.0))
            fixed_model = fix(model; x=1.0)

            @test variable_type(fixed_model, @varname(x)) == FixedParameter
            @test fixed_parameters(fixed_model) == [@varname(x)]
            @test @varname(x) ∉ parameters(fixed_model)
            @test isempty(model_parameters(fixed_model))
            @test @varname(theta) in generated_quantities(fixed_model)
            @test LogDensityProblems.dimension(fixed_model) == 0

            expected_fixed_logp = logpdf(Normal(1, 1), 2.0)
            graph_logp = Base.invokelatest(
                LogDensityProblems.logdensity, fixed_model, Float64[]
            )
            @test graph_logp ≈ expected_fixed_logp

            generated_model = set_evaluation_mode(
                fixed_model, UseGeneratedLogDensityFunction()
            )
            generated_logp = Base.invokelatest(
                LogDensityProblems.logdensity, generated_model, Float64[]
            )
            @test generated_logp ≈ graph_logp

            conditioned_model = condition(model; x=1.0)
            conditioned_logp = Base.invokelatest(
                LogDensityProblems.logdensity, conditioned_model, [0.0]
            )
            expected_conditioned_logp =
                logpdf(Normal(0, 1), 0.0) + logpdf(Normal(0, 1), 1.0) + expected_fixed_logp
            @test conditioned_logp ≈ expected_conditioned_logp
            @test conditioned_logp != graph_logp
        end

        @testset "unfix restores target classification" begin
            model_def = @bugs begin
                theta ~ Normal(0, 1)
                x ~ Normal(theta, 1)
                y ~ Normal(x, 1)
            end

            model = compile(model_def, (; y=2.0))
            fixed_model = fix(model; x=1.0)
            unfixed_model = unfix(fixed_model, @varname(x))

            @test isempty(fixed_parameters(unfixed_model))
            @test variable_type(unfixed_model, @varname(theta)) == ModelParameter
            @test variable_type(unfixed_model, @varname(x)) == ModelParameter
            @test Set(model_parameters(unfixed_model)) ==
                Set([@varname(theta), @varname(x)])
            @test LogDensityProblems.dimension(unfixed_model) == 2
        end

        @testset "fix-induced generated quantities survive later graph surgery" begin
            model_def = @bugs begin
                theta ~ Normal(0, 1)
                x ~ Normal(theta, 1)
                y ~ Normal(x, 1)
                w ~ Normal(0, 1)
            end

            m0 = compile(model_def, (;))
            m1 = condition(m0; y=2.0, w=0.0)
            m2 = fix(m1; x=1.0)

            @test variable_type(m2, @varname(theta)) == GeneratedQuantity
            @test @varname(theta) ∉ model_parameters(m2)

            m3 = decondition(m2, [@varname(w)])

            @test variable_type(m3, @varname(theta)) == GeneratedQuantity
            @test @varname(theta) ∉ model_parameters(m3)
            @test variable_type(m3, @varname(w)) == ModelParameter
            @test model_parameters(m3) == [@varname(w)]
        end

        @testset "fixing with subsumption" begin
            model_def = @bugs begin
                for i in 1:3
                    x[i] ~ Normal(0, 1)
                end
                y ~ Normal(sum(x[:]), 1)
            end

            model = compile(model_def, (; y=6.0))
            fixed_model = @test_logs(
                (
                    :warn,
                    "Variable x does not exist in the model. Fixing subsumed variables instead: x[1], x[2], x[3]",
                ),
                fix(model, Dict(@varname(x) => [1.0, 2.0, 3.0]))
            )

            @test Set(fixed_parameters(fixed_model)) ==
                Set([@varname(x[1]), @varname(x[2]), @varname(x[3])])
            @test isempty(model_parameters(fixed_model))
            @test LogDensityProblems.dimension(fixed_model) == 0

            graph_logp = Base.invokelatest(
                LogDensityProblems.logdensity, fixed_model, Float64[]
            )
            generated_logp = Base.invokelatest(
                LogDensityProblems.logdensity,
                set_evaluation_mode(fixed_model, UseGeneratedLogDensityFunction()),
                Float64[],
            )
            @test generated_logp ≈ graph_logp
        end

        @testset "fix validation" begin
            model_def = @bugs begin
                x ~ Normal(0, 1)
                y = x^2
                z ~ Normal(y, 1)
            end

            model = compile(model_def, (; z=1.0))

            @test_throws ArgumentError fix(model; y=1.0)
            @test_throws ArgumentError fix(model; z=1.0)
        end

        @testset "no-observation prior behavior is preserved" begin
            model_def = @bugs begin
                theta ~ Normal(0, 1)
                x ~ Normal(theta, 1)
            end

            model = compile(model_def, (;))
            fixed_model = fix(model; x=1.0)

            @test variable_type(fixed_model, @varname(x)) == FixedParameter
            @test variable_type(fixed_model, @varname(theta)) == ModelParameter
            @test model_parameters(fixed_model) == [@varname(theta)]
            @test LogDensityProblems.dimension(fixed_model) == 1
        end

        @testset "fixed discrete variables are constants under auto-marginalization" begin
            model_def = @bugs begin
                z ~ Bernoulli(0.25)
                y ~ Bernoulli(0.2 + 0.6 * z)
            end

            model = compile(model_def, (; y=1))
            fixed_model = fix(model; z=1)
            auto_model = set_evaluation_mode(fixed_model, UseAutoMarginalization())

            @test LogDensityProblems.dimension(auto_model) == 0
            @test Base.invokelatest(LogDensityProblems.logdensity, auto_model, Float64[]) ≈
                logpdf(Bernoulli(0.8), 1)
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

        # With lazy generation, functions are not pregenerated
        @test isnothing(model.log_density_computation_function)
        @test isnothing(model_cond.log_density_computation_function)

        # Test evaluation with generated function
        model_cond_gen = set_evaluation_mode(model_cond, UseGeneratedLogDensityFunction())
        @test !isnothing(model_cond_gen.log_density_computation_function)

        params = [2.0]  # Only sigma
        logp1 = Base.invokelatest(LogDensityProblems.logdensity, model_cond_gen, params)

        # Compare with graph evaluation
        model_cond_graph = set_evaluation_mode(model_cond_gen, UseGraph())
        logp2 = Base.invokelatest(LogDensityProblems.logdensity, model_cond_graph, params)

        @test logp1 ≈ logp2
    end
end
