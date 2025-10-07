using JuliaBUGS.Model:
    BUGSModel,
    condition,
    decondition,
    parameters,
    variables,
    getparams,
    settrans,
    set_evaluation_mode,
    UseGeneratedLogDensityFunction,
    UseGraph

@testset "Compile Vol.1 BUGS Examples" begin
    for model_name in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[model_name]
        model = compile(model_def, data, inits)
    end
end

@testset "dot call" begin
    model_def = @bugs begin
        x[1:2] ~ product_distribution(fill(Normal(0, 1), 2))
    end
    model = compile(model_def, (;))
    @test model.evaluation_env.x isa Vector{Float64}
end

@testset "Model Interface Functions" begin
    @testset "parameters and variables" begin
        model_def = @bugs begin
            mu ~ Normal(0, 10)
            sigma ~ Gamma(1, 1)
            for i in 1:3
                x[i] ~ Normal(mu, sigma)
            end
            mean_x = mean(x[:])
            y ~ Normal(mean_x, 1)
        end

        model = compile(model_def, (; y=2.5))

        # Test parameters function
        params = parameters(model)
        @test length(params) == 5  # mu, sigma, x[1], x[2], x[3]
        @test @varname(mu) in params
        @test @varname(sigma) in params
        @test @varname(x[1]) in params
        @test @varname(x[2]) in params
        @test @varname(x[3]) in params
        @test @varname(y) ∉ params  # observed
        @test @varname(mean_x) ∉ params  # deterministic

        # Test variables function
        vars = variables(model)
        @test length(vars) == 7  # mu, sigma, x[1], x[2], x[3], mean_x, y
        @test @varname(mu) in vars
        @test @varname(sigma) in vars
        @test @varname(mean_x) in vars
        @test @varname(y) in vars

        # Test with conditioned model
        model_cond = condition(model, (; mu=0.5))
        params_cond = parameters(model_cond)
        @test length(params_cond) == 4  # sigma, x[1], x[2], x[3]
        @test @varname(mu) ∉ params_cond
        @test @varname(sigma) in params_cond

        # Test warning when conditioning on already observed variable
        model_cond_warn = @test_logs(
            (
                :warn,
                "y is already observed, conditioning on it may not have the expected effect",
            ),
            condition(model, (; y=3.0))
        )
        @test parameters(model_cond_warn) == parameters(model)  # No change in parameters

        # Test warning when conditioning with subsumption
        model_subsume = @test_logs(
            (
                :warn,
                "Variable x does not exist in the model. Conditioning on subsumed variables instead: x[1], x[2], x[3]",
            ),
            condition(model, Dict(@varname(x) => [1.0, 2.0, 3.0]))
        )
        @test length(parameters(model_subsume)) == 2  # Only mu and sigma remain
    end

    @testset "initialize!" begin
        model_def = @bugs begin
            a ~ Normal(0, 1)
            b ~ Normal(a, 1)
            c = a + b
            d ~ Normal(c, 1)
        end

        model = compile(model_def, (; d=3.0))

        @testset "NamedTuple initialization" begin
            # Initialize with specific values
            model_init = initialize!(model, (; a=1.0, b=2.0))
            @test model_init.evaluation_env.a ≈ 1.0
            @test model_init.evaluation_env.b ≈ 2.0
            @test model_init.evaluation_env.c ≈ 3.0  # computed from a + b

            # Partial initialization (missing values are sampled)
            model_partial = initialize!(model, (; a=0.5))
            @test model_partial.evaluation_env.a ≈ 0.5
            @test isa(model_partial.evaluation_env.b, Float64)  # sampled

            # Empty initialization (all sampled)
            model_empty = initialize!(model, (;))
            @test isa(model_empty.evaluation_env.a, Float64)
            @test isa(model_empty.evaluation_env.b, Float64)
        end

        @testset "Vector initialization" begin
            # Initialize with parameter vector
            params = [1.5, 2.5]  # [a, b]
            model_vec = initialize!(model, params)
            @test model_vec.evaluation_env.a ≈ 1.5
            @test model_vec.evaluation_env.b ≈ 2.5

            # Test with transformed parameters
            model_trans = settrans(model, true)
            # For Normal(0,1), transform is identity
            model_vec_trans = initialize!(model_trans, params)
            @test model_vec_trans.evaluation_env.a ≈ 1.5
            @test model_vec_trans.evaluation_env.b ≈ 2.5
        end

        @testset "Array parameters" begin
            model_def = @bugs begin
                for i in 1:3
                    theta[i] ~ Normal(0, 1)
                end
                y ~ Normal(sum(theta[:]), 1)
            end

            model = compile(model_def, (; y=1.0))

            # Initialize with array
            model_init = initialize!(model, (; theta=[1.0, 2.0, 3.0]))
            @test model_init.evaluation_env.theta == [1.0, 2.0, 3.0]

            # Initialize with vector
            params = [0.5, 1.5, 2.5]
            model_vec = initialize!(model, params)
            @test model_vec.evaluation_env.theta == [0.5, 1.5, 2.5]
        end
    end

    @testset "getparams" begin
        model_def = @bugs begin
            mu ~ Normal(0, 10)
            tau ~ Gamma(1, 1)
            for i in 1:3
                x[i] ~ Normal(mu, tau)
            end
        end

        model = compile(model_def, (;))
        model = initialize!(model, (; mu=1.0, tau=2.0, x=[1.5, 2.5, 3.5]))

        @testset "Vector extraction" begin
            # Check parameter order first
            param_names = parameters(model)

            # Default is transformed mode
            params = getparams(model)
            @test length(params) == 5

            # Get params as dict to check order-independent
            params_dict = getparams(Dict, model)
            @test params_dict[@varname(mu)] ≈ 1.0
            @test params_dict[@varname(tau)] ≈ log(2.0)
            @test params_dict[@varname(x[1])] ≈ 1.5

            # Untransformed parameters
            model_untrans = settrans(model, false)
            params_untrans = getparams(model_untrans)
            params_dict_untrans = getparams(Dict, model_untrans)
            @test length(params_untrans) == 5
            @test params_dict_untrans[@varname(mu)] ≈ 1.0
            @test params_dict_untrans[@varname(tau)] ≈ 2.0
            @test params_dict_untrans[@varname(x[1])] ≈ 1.5
        end

        @testset "Dictionary extraction" begin
            # Default is transformed
            params_dict = getparams(Dict, model)
            @test params_dict[@varname(mu)] ≈ 1.0
            @test params_dict[@varname(tau)] ≈ log(2.0)  # transformed
            @test params_dict[@varname(x[1])] ≈ 1.5

            # Untransformed
            model_untrans = settrans(model, false)
            params_dict_untrans = getparams(Dict, model_untrans)
            @test params_dict_untrans[@varname(mu)] ≈ 1.0
            @test params_dict_untrans[@varname(tau)] ≈ 2.0  # untransformed

            # Different dict type
            using OrderedCollections
            params_ordered = getparams(OrderedDict, model)
            @test params_ordered isa OrderedDict
            @test params_ordered[@varname(mu)] ≈ 1.0
        end

        @testset "With conditioned model" begin
            model_cond = condition(model, (; mu=0.5))

            # Only unconditioned parameters (default transformed)
            params = getparams(model_cond)
            @test length(params) == 4  # tau, x[1:3]
            @test params[1] ≈ log(2.0)  # tau transformed
            @test params[2:4] == [1.5, 2.5, 3.5]

            params_dict = getparams(Dict, model_cond)
            @test !haskey(params_dict, @varname(mu))
            @test params_dict[@varname(tau)] ≈ log(2.0)  # transformed
        end
    end

    @testset "settrans" begin
        model_def = @bugs begin
            a ~ Normal(0, 1)
            b ~ Gamma(1, 1)
            c ~ Beta(1, 1)
        end

        model = compile(model_def, (;))

        # Default is transformed
        @test model.transformed == true

        # Switch to untransformed
        model_untrans = settrans(model, false)
        @test model_untrans.transformed == false
        @test model.transformed == true  # original unchanged

        # Switch back using default
        model_trans = settrans(model_untrans)
        @test model_trans.transformed == true

        # Test parameter length consistency
        @test model.untransformed_param_length == 3
        @test model.transformed_param_length == 3  # all scalars

        @testset "Interaction with evaluation mode" begin
            # Can't use untransformed with generated function
            model_gen = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
            @test_throws ErrorException settrans(model_gen, false)

            # But can with graph mode
            model_graph = set_evaluation_mode(model, UseGraph())
            model_untrans = settrans(model_graph, false)
            @test model_untrans.transformed == false
        end
    end

    @testset "set_evaluation_mode" begin
        model_def = @bugs begin
            x ~ Normal(0, 1)
            y ~ Normal(x, 1)
            z ~ Normal(y, 1)
        end

        model = compile(model_def, (; z=2.5))

        # Default is UseGraph
        @test model.evaluation_mode isa UseGraph

        @testset "Switching modes" begin
            # Switch to generated function
            model_gen = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
            @test model_gen.evaluation_mode isa UseGeneratedLogDensityFunction
            @test model.evaluation_mode isa UseGraph  # original unchanged

            # Switch back to graph
            model_graph = set_evaluation_mode(model_gen, UseGraph())
            @test model_graph.evaluation_mode isa UseGraph
        end

        @testset "Generated function availability" begin
            # Test behavior when model doesn't support generated function
            # Create a model that doesn't have a generated function
            model_no_gen = compile(model_def, (; z=2.5))
            # Manually set the log_density_computation_function to nothing to simulate
            # a model without generated function support
            model_no_gen_modified = BUGSModel(
                model_no_gen; log_density_computation_function=nothing
            )

            # Verify the function is indeed nothing
            @test model_no_gen_modified.log_density_computation_function === nothing
            @test model_no_gen_modified.evaluation_mode isa UseGraph

            # When setting to UseGeneratedLogDensityFunction, it should automatically
            # fall back to UseGraph mode since no generated function is available
            # Test both the warning and the behavior
            model_attempt = @test_logs (:warn,) set_evaluation_mode(
                model_no_gen_modified, UseGeneratedLogDensityFunction()
            )
            @test model_attempt.evaluation_mode isa UseGraph

            # Verify that a normal model with generated function works as expected
            model_with_gen = compile(model_def, (; z=2.5))
            @test !isnothing(model_with_gen.log_density_computation_function)
            model_gen_mode = set_evaluation_mode(
                model_with_gen, UseGeneratedLogDensityFunction()
            )
            @test model_gen_mode.evaluation_mode isa UseGeneratedLogDensityFunction
        end

        @testset "Interaction with transformed" begin
            # Can't use generated function with untransformed
            model_untrans = settrans(model, false)
            @test_throws ErrorException set_evaluation_mode(
                model_untrans, UseGeneratedLogDensityFunction()
            )
        end

        @testset "Performance difference" begin
            # Both modes should give same result
            model_gen = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
            model_graph = set_evaluation_mode(model, UseGraph())

            params = [0.5, 1.0]  # x, y
            logp_gen = LogDensityProblems.logdensity(model_gen, params)
            logp_graph = LogDensityProblems.logdensity(model_graph, params)

            @test logp_gen ≈ logp_graph
        end
    end

    @testset "Integration tests" begin
        @testset "Full workflow" begin
            # Define model
            model_def = @bugs begin
                mu ~ Normal(0, 10)
                sigma ~ Gamma(1, 1)
                for i in 1:5
                    y[i] ~ Normal(mu, sigma)
                end
            end

            # Compile with data
            data = (; y=[1.0, 2.0, 1.5, 2.5, 1.8])
            model = compile(model_def, data)

            # Check basic properties
            @test length(parameters(model)) == 2
            @test length(variables(model)) == 7

            # Initialize
            model = initialize!(model, (; mu=1.5, sigma=0.5))

            # Get parameters (default transformed)
            params = getparams(model)
            @test length(params) == 2
            params_dict = getparams(Dict, model)
            @test params_dict[@varname(mu)] ≈ 1.5  # mu (identity transform)
            @test params_dict[@varname(sigma)] ≈ log(0.5)  # sigma (log transformed)

            # Condition on mu
            model_cond = condition(model, (; mu=2.0))
            @test length(parameters(model_cond)) == 1
            @test parameters(model_cond) == [@varname(sigma)]

            # Switch to untransformed
            model_untrans = settrans(model_cond, false)
            params_untrans = getparams(model_untrans)
            @test length(params_untrans) == 1
            @test params_untrans[1] ≈ 0.5

            # Decondition
            model_decond = decondition(model_cond)
            @test length(parameters(model_decond)) == 2
            @test Set(parameters(model_decond)) == Set([@varname(mu), @varname(sigma)])
        end

        @testset "Model show method" begin
            model_def = @bugs begin
                alpha ~ Normal(0, 1)
                beta[1] ~ Normal(0, 1)
                beta[2] ~ Normal(0, 1)
                sigma ~ Gamma(1, 1)
            end

            model = compile(model_def, (;))

            # Test that show doesn't error
            io = IOBuffer()
            show(io, model)
            output = String(take!(io))

            @test occursin("BUGSModel", output)
            @test occursin("Model parameters:", output)
            @test occursin("alpha", output)
            @test occursin("beta", output)
            @test occursin("sigma", output)
            @test occursin("Variable sizes and types:", output)
        end
    end

    @testset "AD Type Parameter" begin
        model_def = @bugs begin
            mu ~ dnorm(0, 1)
            y ~ dnorm(mu, 1)
        end
        data = (y=1.5,)

        @testset "ADTypes backends" begin
            # Test with compile=true
            model_compile = compile(model_def, data; adtype=AutoReverseDiff(; compile=true))
            @test model_compile isa JuliaBUGS.Model.BUGSModelWithGradient

            # Test with compile=false
            model_nocompile = compile(
                model_def, data; adtype=AutoReverseDiff(; compile=false)
            )
            @test model_nocompile isa JuliaBUGS.Model.BUGSModelWithGradient
        end

        @testset "Default behavior (no adtype)" begin
            # Without adtype, should return regular BUGSModel
            model_default = compile(model_def, data)
            @test model_default isa BUGSModel
            @test !(model_default isa JuliaBUGS.Model.BUGSModelWithGradient)
        end

        @testset "Gradient computation" begin
            model = compile(model_def, data; adtype=AutoReverseDiff(; compile=true))
            test_point = [0.0]

            # Test that gradient can be computed
            ℓ, grad = LogDensityProblems.logdensity_and_gradient(model, test_point)

            @test ℓ isa Real
            @test grad isa Vector
            @test length(grad) == 1
            @test isfinite(ℓ)
            @test all(isfinite, grad)
        end
    end
end
