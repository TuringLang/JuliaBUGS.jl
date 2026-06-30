using BangBang
using Bijectors
using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using LogDensityProblems
using OrderedCollections

test_examples = [
    :rats,
    :pumps,
    :dogs,
    :seeds,
    :surgical_realistic,
    :magnesium,
    :salm,
    :equiv,
    :dyes,
    :stacks,
    :epil,
    :blockers,
    :oxford,
    :lsat,
    :bones,
    :mice,
    :kidney,
    :leuk,
    :leukfr,
    :dugongs,
    :air,
    :birats,
    :schools,
    :cervix,
]

@testset "source_gen: $example_name" for example_name in test_examples
    (; model_def, data, inits) = getfield(JuliaBUGS.BUGSExamples, example_name)
    model = compile(model_def, data, inits)

    # Test with graph evaluation
    result_with_bugsmodel = begin
        model_graph = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
        params_graph = Base.invokelatest(JuliaBUGS.getparams, model_graph)
        Base.invokelatest(LogDensityProblems.logdensity, model_graph, params_graph)
    end

    # Test with generated function (triggers on-demand generation)
    result_with_log_density_computation_function = begin
        model_gen = JuliaBUGS.set_evaluation_mode(
            model, JuliaBUGS.UseGeneratedLogDensityFunction()
        )
        # Explicitly check that source generation succeeded
        @test !isnothing(model_gen.log_density_computation_function)
        # Extract params after setting mode to account for potential parameter reordering
        params_gen = Base.invokelatest(JuliaBUGS.getparams, model_gen)
        Base.invokelatest(LogDensityProblems.logdensity, model_gen, params_gen)
    end

    @test result_with_log_density_computation_function ≈ result_with_bugsmodel
end

@testset "reserved variable names are rejected" begin
    @test_throws ErrorException JuliaBUGS.__check_for_reserved_names(
        JuliaBUGS.Parser.bugs_top(:(begin
            __logp__ ~ dnorm(0, 1)
        end))
    )
end

@testset "mixed data transformation and deterministic assignments" begin
    model_def = @bugs begin
        for i in 1:5
            y[i] ~ Normal(0, 1)
        end
        for i in 1:5
            x[i] = y[i] + 1
        end
    end
    data = (; y=[1, 2, missing, missing, 2])

    model = compile(model_def, data)
end

@testset "state-space models (SSM) transformation" begin
    # Helper: check if source generation succeeds, returns (success::Bool, diagnostics)
    function can_generate_source(model_def, data)
        model_def = model_def isa JuliaBUGS.BUGSModelDef ? model_def.model_def : model_def
        eval_env = JuliaBUGS.semantic_analysis(model_def, data)
        g = JuliaBUGS.create_graph(model_def, eval_env)
        diags = String[]
        lowered, reconstructed = JuliaBUGS._generate_lowered_model_def(
            model_def, g, eval_env; diagnostics=diags
        )
        return lowered !== nothing, diags
    end

    # Helper: verify generated code produces same log density as graph evaluation
    function generated_matches_graph(model_def, data)
        model = compile(model_def, data)
        result_graph = begin
            m = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
            params = Base.invokelatest(JuliaBUGS.getparams, m)
            Base.invokelatest(LogDensityProblems.logdensity, m, params)
        end
        result_gen = begin
            m = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())
            params = Base.invokelatest(JuliaBUGS.getparams, m)
            Base.invokelatest(LogDensityProblems.logdensity, m, params)
        end
        return result_graph ≈ result_gen
    end

    @testset "basic SSM with self-recursion" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(x[t - 1], sigma_x)
            end
            for t in 1:T
                y[t] ~ Normal(x[t], sigma_y)
            end
        end
        data = (T=10, sigma_x=0.5, sigma_y=0.3)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "lagged observations" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(x[t - 1], sigma_x)
            end
            y[1] ~ Normal(x[1], sigma_y)
            for t in 2:T
                y[t] ~ Normal(x[t - 1], sigma_y)
            end
        end
        data = (T=10, sigma_x=0.5, sigma_y=0.3)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "cross-coupled SSM (mutual lag-1)" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            y[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(y[t - 1], sigma_x)
                y[t] ~ Normal(x[t - 1], sigma_y)
            end
        end
        data = (T=10, sigma_x=0.5, sigma_y=0.3)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "negative dependence (read future) rejected" begin
        model_def = @bugs begin
            for t in 1:(T - 1)
                x[t] ~ Normal(x[t + 1], sigma)
            end
            x[T] ~ Normal(0, 1)
        end
        @test !first(can_generate_source(model_def, (T=10, sigma=0.7)))
    end

    @testset "grid SSM (multi-dimensional)" begin
        model_def = @bugs begin
            for i in 1:I
                x[i, 1] ~ Normal(0, 1)
                for t in 2:T
                    x[i, t] ~ Normal(x[i, t - 1], sigma)
                end
            end
            for i in 1:I
                for t in 1:T
                    y[i, t] ~ Normal(x[i, t], sigma_y)
                end
            end
        end
        data = (I=3, T=10, sigma=0.7, sigma_y=0.3)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "inter-loop cycle rejected" begin
        # Even/odd split loops with mutual dependencies cannot be fused automatically
        model_def = @bugs begin
            sumX[1] = x[1]
            for i in 2:N
                sumX[i] = sumX[i - 1] + x[i]
            end
            for k in 1:K
                x[2 * k] ~ Normal(sumX[2 * k - 1], tau)
            end
            for k in 1:Km1
                x[2 * k + 1] ~ Gamma(sumX[2 * k], tau)
            end
        end
        data = (N=10, K=5, Km1=4, tau=1.2, x=Union{Float64,Missing}[1.0; fill(missing, 9)])
        @test !first(can_generate_source(model_def, data))
    end

    @testset "deterministic cycle rejected" begin
        # Cyclic deterministic dependencies cannot be resolved
        model_def = @bugs begin
            z[1] = 0.0
            z[2] = x[1] + 0.0
            y[1] = 0.0
            y[2] = x[3] + 0.0
            for i in 1:3
                x[i] = y[a[i]] + z[b[i]]
            end
        end
        @test !first(can_generate_source(model_def, (a=[2, 2, 1], b=[2, 1, 2])))
    end

    @testset "multi-statement loop with mixed dependencies" begin
        # Self-recursion (positive) + same-iteration dependency (zero)
        # Should stay as single fused loop with correct intra-iteration order
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            y[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(x[t - 1], sigma)  # positive self-dep
                y[t] ~ Normal(x[t], sigma)       # zero dep (same iteration)
            end
        end
        data = (T=10, sigma=0.5)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "three-way cross-coupled SSM" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            y[1] ~ Normal(0, 1)
            z[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(y[t - 1] + z[t - 1], sigma)
                y[t] ~ Normal(x[t - 1] + z[t - 1], sigma)
                z[t] ~ Normal(x[t - 1] + y[t - 1], sigma)
            end
        end
        data = (T=10, sigma=0.5)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "@bugs_primitive works with UseGeneratedLogDensityFunction" begin
        my_square(x) = x^2
        JuliaBUGS.@bugs_primitive my_square

        model_def = @bugs begin
            x ~ dnorm(0, 1)
            y = my_square(x)
            z ~ dnorm(y, 1)
        end

        model = compile(model_def, (z=1.0,))
        model_graph = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
        model_gen = JuliaBUGS.set_evaluation_mode(
            model, JuliaBUGS.UseGeneratedLogDensityFunction()
        )

        params = Base.invokelatest(JuliaBUGS.getparams, model_graph)
        ld_graph = Base.invokelatest(LogDensityProblems.logdensity, model_graph, params)
        ld_gen = Base.invokelatest(LogDensityProblems.logdensity, model_gen, params)

        @test isapprox(ld_graph, ld_gen; rtol=1e-10)
    end
end

@testset "generated quantities in generated log-density function" begin
    # A generated quantity (GQ) is an unobserved node (stochastic or deterministic) that
    # cannot reach any observation, so it contributes nothing to the model log density and
    # the generated function must drop its `~`/`=` statement entirely. The helper below
    # asserts the invariants the feature must uphold for each model:
    #
    #   I1  Mode-invariance: `model_parameters`, `generated_quantities`, and `dimension`
    #       are identical between `UseGraph` and `UseGeneratedLogDensityFunction`. (This is
    #       exactly what the conditioning/regeneration consistency bug used to violate.)
    #   I2  Partition: a node is never both a model parameter and a generated quantity, and
    #       `model_parameters ⊆ parameters ⊆ model_parameters ∪ generated_quantities`
    #       (`parameters` additionally holds the stochastic generated quantities).
    #   I3  Dimension reflects model parameters only: `dimension == length(getparams)` and
    #       no generated quantity appears in the parameter vector.
    #   I4  Generated ≡ graph: equal log density at matched parameter values, flattening
    #       parameters in each model's own ordering (the generated model re-orders nodes to
    #       loop-execution order).
    #   I5  Generated quantities do not enter the log density: re-forward-sampling the GQ
    #       (which changes only GQ values, leaving parameters and observations fixed) leaves
    #       both `getparams` and the log density unchanged, in both modes.
    JuliaBUGS.@bugs_primitive Normal

    forward_sample_generated_quantities =
        JuliaBUGS.Model.forward_sample_generated_quantities!!

    # `n_params` is the number of (scalar) model parameters = the expected `dimension`;
    # `n_gq` the number of generated-quantity nodes; `has_stochastic_gq` whether at least
    # one GQ is stochastic (so re-sampling actually perturbs the environment).
    function check_gq_invariants(model; n_params, n_gq, has_stochastic_gq)
        graph_model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
        generated_model = JuliaBUGS.set_evaluation_mode(
            model, JuliaBUGS.UseGeneratedLogDensityFunction()
        )
        @test !isnothing(generated_model.log_density_computation_function)

        model_parameter_set = Set(JuliaBUGS.model_parameters(graph_model))
        generated_quantity_set = Set(JuliaBUGS.generated_quantities(graph_model))
        parameter_set = Set(JuliaBUGS.parameters(graph_model))
        dimension = LogDensityProblems.dimension(graph_model)

        # I1: classification and dimension do not depend on the evaluation mode.
        @test Set(JuliaBUGS.model_parameters(generated_model)) == model_parameter_set
        @test Set(JuliaBUGS.generated_quantities(generated_model)) == generated_quantity_set
        @test Set(JuliaBUGS.parameters(generated_model)) == parameter_set
        @test LogDensityProblems.dimension(generated_model) == dimension

        # Per-model anchors so a silent reclassification can't pass unnoticed.
        @test length(model_parameter_set) == n_params
        @test length(generated_quantity_set) == n_gq
        @test dimension == n_params

        # I2: model parameters and generated quantities partition the unobserved
        # stochastic nodes; `parameters` is their union (it also lists stochastic GQ).
        @test isempty(intersect(model_parameter_set, generated_quantity_set))
        @test issubset(model_parameter_set, parameter_set)
        @test issubset(parameter_set, union(model_parameter_set, generated_quantity_set))

        # I3: the parameter vector covers exactly the model parameters; no GQ leaks in.
        @test length(JuliaBUGS.getparams(graph_model)) == dimension
        param_keys = Set(keys(JuliaBUGS.getparams(Dict, graph_model)))
        @test param_keys == model_parameter_set
        @test isempty(intersect(param_keys, generated_quantity_set))

        # I4: generated log density matches graph evaluation at matched values.
        for seed in 1:8
            env, _ = Base.invokelatest(
                JuliaBUGS.AbstractPPL.evaluate!!, Random.MersenneTwister(seed), model
            )
            graph_parameters = JuliaBUGS.getparams(graph_model, env)
            generated_parameters = JuliaBUGS.getparams(generated_model, env)
            @test length(graph_parameters) == length(generated_parameters) == dimension
            graph_logdensity = Base.invokelatest(
                LogDensityProblems.logdensity, graph_model, graph_parameters
            )
            generated_logdensity = Base.invokelatest(
                LogDensityProblems.logdensity, generated_model, generated_parameters
            )
            @test isapprox(graph_logdensity, generated_logdensity; atol=1e-10)
        end

        # I5: log density is invariant to the values of generated quantities. Two forward
        # samples differ only in their GQ values; parameters and log density must not move.
        base_env, _ = Base.invokelatest(
            JuliaBUGS.AbstractPPL.evaluate!!, Random.MersenneTwister(99), model
        )
        # This helper calls the compiled node functions directly, so invoke it in the latest
        # world age (the helper is defined before these models are compiled).
        env_a = Base.invokelatest(
            forward_sample_generated_quantities,
            Random.MersenneTwister(1),
            model,
            deepcopy(base_env),
        )
        env_b = Base.invokelatest(
            forward_sample_generated_quantities,
            Random.MersenneTwister(2),
            model,
            deepcopy(base_env),
        )
        @test JuliaBUGS.getparams(graph_model, env_a) ==
            JuliaBUGS.getparams(graph_model, env_b)
        if has_stochastic_gq
            # Guard against a vacuous test: the GQ values really did change.
            @test any(
                vn ->
                    JuliaBUGS.AbstractPPL.getvalue(env_a, vn) !=
                    JuliaBUGS.AbstractPPL.getvalue(env_b, vn),
                generated_quantity_set,
            )
        end
        for m in (graph_model, generated_model)
            m_a = BangBang.setproperty!!(m, :evaluation_env, env_a)
            m_b = BangBang.setproperty!!(m, :evaluation_env, env_b)
            lp_a = Base.invokelatest(
                LogDensityProblems.logdensity, m_a, JuliaBUGS.getparams(m_a)
            )
            lp_b = Base.invokelatest(
                LogDensityProblems.logdensity, m_b, JuliaBUGS.getparams(m_b)
            )
            @test isapprox(lp_a, lp_b; atol=1e-10)
        end
        return nothing
    end

    @testset "scalar GQ (stochastic + deterministic)" begin
        # z and pred are generated quantities; only mu is a parameter.
        check_gq_invariants(
            compile((@bugs begin
                mu ~ Normal(0, 1)
                y ~ Normal(mu, 1)
                z ~ Normal(mu, 1)
                pred = mu + 1.0
            end), (; y=0.5));
            n_params=1,
            n_gq=2,
            has_stochastic_gq=true,
        )
    end

    @testset "_generate_lowered_model_def derives GQ classification by default" begin
        model = compile((@bugs begin
            mu ~ Normal(0, 1)
            y ~ Normal(mu, 1)
            z ~ Normal(mu, 1)
            pred = mu + 1.0
        end), (; y=0.5))

        lowered_default, _ = JuliaBUGS._generate_lowered_model_def(
            model.model_def, model.g, model.evaluation_env
        )
        lowered_cached, _ = JuliaBUGS._generate_lowered_model_def(
            model.model_def,
            model.g,
            model.evaluation_env;
            generated_quantities=Set(JuliaBUGS.generated_quantities(model)),
        )
        @test lowered_default == lowered_cached
    end

    @testset "prior-only deterministic ancestor of stochastic parameter" begin
        model = compile((@bugs begin
            x ~ Normal(0, 1)
            h = x + 1
            y ~ Normal(h, 1)
        end), (;))

        @test JuliaBUGS.variable_type(model, @varname(h)) == JuliaBUGS.TransformedParameter
        check_gq_invariants(model; n_params=2, n_gq=0, has_stochastic_gq=false)

        graph_model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
        generated_model = JuliaBUGS.set_evaluation_mode(
            model, JuliaBUGS.UseGeneratedLogDensityFunction()
        )
        for values in ([0.0, 0.0], [1.0, 2.0], [-2.0, 0.5])
            @test LogDensityProblems.logdensity(graph_model, values) ≈
                LogDensityProblems.logdensity(generated_model, values)
        end
    end

    @testset "chained GQ" begin
        # z and z2 form a GQ chain hanging off mu.
        check_gq_invariants(
            compile((@bugs begin
                mu ~ Normal(0, 1)
                y ~ Normal(mu, 1)
                z ~ Normal(mu, 1)
                z2 ~ Normal(z, 1)
            end), (; y=0.5));
            n_params=1,
            n_gq=2,
            has_stochastic_gq=true,
        )
    end

    @testset "all-GQ loop (entirely dropped)" begin
        # The whole g[1:3] loop is generated quantities and must drop out.
        check_gq_invariants(
            compile((@bugs begin
                mu ~ Normal(0, 1)
                y ~ Normal(mu, 1)
                for i in 1:3
                    g[i] ~ Normal(mu, 1)
                end
            end), (; y=0.5));
            n_params=1,
            n_gq=3,
            has_stochastic_gq=true,
        )
    end

    @testset "partial-observation loop (observed + GQ siblings)" begin
        # y[2], y[4] are missing with no observed descendant -> generated quantities.
        check_gq_invariants(
            compile((@bugs begin
                mu ~ Normal(0, 1)
                for i in 1:4
                    y[i] ~ Normal(mu, 1)
                end
            end), (; y=[0.1, missing, 0.3, missing]));
            n_params=1,
            n_gq=2,
            has_stochastic_gq=true,
        )
    end

    @testset "single statement mixes observed, parameter, and GQ iterations" begin
        model = compile(
            (@bugs begin
                mu ~ Normal(0, 1)
                for i in 1:3
                    y[i] ~ Normal(mu, 1)
                    z[i] ~ Normal(y[i], 1)
                end
            end),
            (; y=[0.1, missing, missing], z=[missing, 0.2, missing]),
        )

        @test JuliaBUGS.variable_type(model, @varname(y[1])) == JuliaBUGS.Observation
        @test JuliaBUGS.variable_type(model, @varname(y[2])) == JuliaBUGS.ModelParameter
        @test JuliaBUGS.variable_type(model, @varname(y[3])) == JuliaBUGS.GeneratedQuantity
        check_gq_invariants(model; n_params=2, n_gq=3, has_stochastic_gq=true)
    end

    @testset "mixed loops (observed + parameter in x, observed + GQ in z)" begin
        # x[1], x[3] are parameters; x[2], x[4] observed; z[1], z[3] observed
        # likelihoods; z[2], z[4] are generated quantities.
        check_gq_invariants(
            compile(
                (@bugs begin
                    for i in 1:4
                        x[i] ~ Normal(0, 1)
                        z[i] ~ Normal(x[i], 1)
                    end
                end),
                (; x=[missing, 1.0, missing, 2.0], z=[0.5, missing, 0.7, missing]),
            );
            n_params=2,
            n_gq=2,
            has_stochastic_gq=true,
        )
    end

    @testset "conditioning preserves classification (no-data model)" begin
        # Compiling without data treats every node as a parameter (no-data shim). After
        # conditioning x[1], x[3] the remaining x[2], y[1:3] stay parameters -- they must
        # not be silently reclassified as generated quantities when the function is
        # generated. This is the scenario the consistency bug broke.
        model = compile((@bugs begin
            for i in 1:3
                x[i] ~ Normal(0, 1)
            end
            for i in 1:3
                y[i] ~ Normal(x[i], 1)
            end
        end), (;))
        conditioned_model = condition(
            model, Dict(@varname(x[1]) => 0.5, @varname(x[3]) => 1.5)
        )
        check_gq_invariants(conditioned_model; n_params=4, n_gq=0, has_stochastic_gq=false)
    end

    @testset "conditioning preserves a surviving generated quantity" begin
        # z is a generated quantity of the original model; conditioning the only parameter
        # mu must leave z classified as a generated quantity (preserved override) while the
        # parameter space collapses to empty.
        model = compile((@bugs begin
            mu ~ Normal(0, 1)
            y ~ Normal(mu, 1)
            z ~ Normal(mu, 1)
        end), (; y=0.5))
        conditioned_model = condition(model, Dict(@varname(mu) => 0.3))
        check_gq_invariants(conditioned_model; n_params=0, n_gq=1, has_stochastic_gq=true)
    end
end
