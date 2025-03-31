using Test
using Distributions
using Graphs
using JuliaBUGS.ProbabilisticGraphicalModels:
    BayesianNetwork,
    translate_BUGSGraph_to_BayesianNetwork,
    add_stochastic_vertex!,
    add_deterministic_vertex!,
    add_edge!,
    condition,
    decondition,
    ancestral_sampling,
    is_conditionally_independent,
    evaluate,
    evaluate_with_values,
    evaluate_with_marginalization
using BangBang
using JuliaBUGS
using JuliaBUGS: @bugs, compile, NodeInfo, VarName
using Bijectors: Bijectors
using AbstractPPL

@testset "BayesianNetwork" begin
    @testset "Adding vertices" begin
        bn = BayesianNetwork{Symbol}()

        # Test adding stochastic vertex
        id1 = add_stochastic_vertex!(bn, :A, Normal(0, 1), false, :continuous)
        @test id1 == 1
        @test length(bn.names) == 1
        @test bn.names[1] == :A
        @test bn.names_to_ids[:A] == 1
        @test bn.is_stochastic[1] == true
        @test bn.is_observed[1] == false
        @test length(bn.stochastic_ids) == 1

        # Test adding deterministic vertex
        f(x) = x^2
        id2 = add_deterministic_vertex!(bn, :B, f)
        @test id2 == 2
        @test length(bn.names) == 2
        @test bn.names[2] == :B
        @test bn.names_to_ids[:B] == 2
        @test bn.is_stochastic[2] == false
        @test bn.is_observed[2] == false
        @test length(bn.deterministic_ids) == 1
    end

    @testset "Adding edges" begin
        bn = BayesianNetwork{Symbol}()
        add_stochastic_vertex!(bn, :A, Normal(0, 1), false, :continuous)
        add_stochastic_vertex!(bn, :B, Normal(0, 1), false, :continuous)

        add_edge!(bn, :A, :B)
        @test has_edge(bn.graph, 1, 2)
    end

    @testset "conditioning and deconditioning" begin
        bn = BayesianNetwork{Symbol}()
        # Add some vertices
        add_stochastic_vertex!(bn, :A, Normal(0, 1), false, :continuous)
        add_stochastic_vertex!(bn, :B, Normal(0, 1), false, :continuous)
        add_stochastic_vertex!(bn, :C, Normal(0, 1), false, :continuous)

        # Test conditioning
        bn_cond = condition(bn, Dict(:A => 1.0))
        @test bn_cond.is_observed[1] == true
        @test bn_cond.evaluation_env[:A] == 1.0
        @test bn_cond.is_observed[2] == false
        @test bn_cond.is_observed[3] == false

        # Ensure original bn is not mutated
        @test bn.is_observed[1] == false
        @test !haskey(bn.evaluation_env, :A)

        # Test conditioning multiple variables
        bn_cond2 = condition(bn_cond, Dict(:B => 2.0))
        @test bn_cond2.is_observed[1] == true
        @test bn_cond2.is_observed[2] == true
        @test bn_cond2.evaluation_env[:A] == 1.0
        @test bn_cond2.evaluation_env[:B] == 2.0

        # Ensure bn_cond is not mutated
        @test bn_cond.is_observed[2] == false
        @test !haskey(bn_cond.evaluation_env, :B)

        # Test deconditioning
        bn_decond = decondition(bn_cond2, [:A])
        @test bn_decond.is_observed[1] == false
        @test bn_decond.is_observed[2] == true
        @test bn_decond.evaluation_env[:B] == 2.0

        # Ensure bn_cond2 is not mutated
        @test bn_cond2.is_observed[1] == true
        @test bn_cond2.evaluation_env[:A] == 1.0

        # Test deconditioning all
        bn_decond_all = decondition(bn_cond2)
        @test all(.!bn_decond_all.is_observed)

        # Ensure bn_cond2 is still not mutated
        @test bn_cond2.is_observed[1] == true
        @test bn_cond2.is_observed[2] == true
        @test bn_cond2.evaluation_env[:A] == 1.0
        @test bn_cond2.evaluation_env[:B] == 2.0
    end

    @testset "Simple ancestral sampling" begin
        bn = BayesianNetwork{Symbol}()
        # Add stochastic vertices
        add_stochastic_vertex!(bn, :A, Normal(0, 1), false, :continuous)
        add_stochastic_vertex!(bn, :B, Normal(1, 2), false, :continuous)
        # Add deterministic vertex C = A + B
        add_deterministic_vertex!(bn, :C, (a, b) -> a + b)
        add_edge!(bn, :A, :C)
        add_edge!(bn, :B, :C)
        samples = ancestral_sampling(bn)
        @test haskey(samples, :A)
        @test haskey(samples, :B)
        @test haskey(samples, :C)
        @test samples[:A] isa Number
        @test samples[:B] isa Number
        @test samples[:C] ≈ samples[:A] + samples[:B]
    end

    @testset "Complex ancestral sampling" begin
        bn = BayesianNetwork{Symbol}()
        add_stochastic_vertex!(bn, :μ, Normal(0, 2), false, :continuous)
        add_stochastic_vertex!(bn, :σ, LogNormal(0, 0.5), false, :continuous)
        add_stochastic_vertex!(bn, :X, Normal(0, 1), false, :continuous)
        add_stochastic_vertex!(bn, :Y, Normal(0, 1), false, :continuous)
        add_deterministic_vertex!(bn, :X_scaled, (μ, σ, x) -> x * σ + μ)
        add_deterministic_vertex!(bn, :Y_scaled, (μ, σ, y) -> y * σ + μ)
        add_deterministic_vertex!(bn, :Sum, (x, y) -> x + y)
        add_deterministic_vertex!(bn, :Product, (x, y) -> x * y)
        add_deterministic_vertex!(bn, :N, () -> 2.0)
        add_deterministic_vertex!(bn, :Mean, (s, n) -> s / n)
        add_edge!(bn, :μ, :X_scaled)
        add_edge!(bn, :σ, :X_scaled)
        add_edge!(bn, :X, :X_scaled)
        add_edge!(bn, :μ, :Y_scaled)
        add_edge!(bn, :σ, :Y_scaled)
        add_edge!(bn, :Y, :Y_scaled)
        add_edge!(bn, :X_scaled, :Sum)
        add_edge!(bn, :Y_scaled, :Sum)
        add_edge!(bn, :X_scaled, :Product)
        add_edge!(bn, :Y_scaled, :Product)
        add_edge!(bn, :Sum, :Mean)
        add_edge!(bn, :N, :Mean)
        samples = ancestral_sampling(bn)

        @test all(
            haskey(samples, k) for
            k in [:μ, :σ, :X, :Y, :X_scaled, :Y_scaled, :Sum, :Product, :Mean, :N]
        )

        @test all(samples[k] isa Number for k in keys(samples))
        @test samples[:X_scaled] ≈ samples[:X] * samples[:σ] + samples[:μ]
        @test samples[:Y_scaled] ≈ samples[:Y] * samples[:σ] + samples[:μ]
        @test samples[:Sum] ≈ samples[:X_scaled] + samples[:Y_scaled]
        @test samples[:Product] ≈ samples[:X_scaled] * samples[:Y_scaled]
        @test samples[:Mean] ≈ samples[:Sum] / samples[:N]
        @test samples[:N] ≈ 2.0
        @test samples[:σ] > 0
        # Multiple samples test
        n_samples = 1000
        means = zeros(n_samples)
        for i in 1:n_samples
            samples = ancestral_sampling(bn)
            means[i] = samples[:Mean]
        end

        @test mean(means) ≈ 0 atol = 0.5
        @test std(means) > 0
    end

    @testset "Bayes Ball" begin
        @testset "Chain Structure (A → B → C)" begin
            bn = BayesianNetwork{Symbol}()

            add_stochastic_vertex!(bn, :A, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :C, Normal(), false, :continuous)

            add_edge!(bn, :A, :B)
            add_edge!(bn, :B, :C)

            @test is_conditionally_independent(bn, :A, :C, [:B])
            @test !is_conditionally_independent(bn, :A, :C, Symbol[])
        end

        @testset "Fork Structure (A ← B → C)" begin
            bn = BayesianNetwork{Symbol}()

            add_stochastic_vertex!(bn, :A, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :C, Normal(), false, :continuous)

            add_edge!(bn, :B, :A)
            add_edge!(bn, :B, :C)

            @test is_conditionally_independent(bn, :A, :C, [:B])
        end

        @testset "Collider Structure (A → B ← C)" begin
            bn = BayesianNetwork{Symbol}()

            add_stochastic_vertex!(bn, :A, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :C, Normal(), false, :continuous)

            add_edge!(bn, :A, :B)
            add_edge!(bn, :C, :B)

            @test is_conditionally_independent(bn, :A, :C, Symbol[])
            @test !is_conditionally_independent(bn, :A, :C, [:B])
        end

        @testset "Bayes Ball Algorithm Tests" begin
            # Create a simple network: A → B → C
            bn = BayesianNetwork{Symbol}()
            add_stochastic_vertex!(bn, :A, Normal(0, 1), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(0, 1), false, :continuous)
            add_stochastic_vertex!(bn, :C, Normal(0, 1), false, :continuous)
            add_edge!(bn, :A, :B)
            add_edge!(bn, :B, :C)
            @testset "Corner Case: X or Y in Z" begin
                # Test case where X is in Z
                @test is_conditionally_independent(bn, :A, :C, [:A])  # A ⊥ C | A
                # Test case where Y is in Z
                @test is_conditionally_independent(bn, :A, :C, [:C])  # A ⊥ C | C
                # Test case where both X and Y are in Z
                @test is_conditionally_independent(bn, :A, :C, [:A, :C])  # A ⊥ C | A, C
            end
        end

        @testset "Complex Structure" begin
            bn = BayesianNetwork{Symbol}()

            for v in [:A, :B, :C, :D, :E]
                add_stochastic_vertex!(bn, v, Normal(), false, :continuous)
            end

            # Create structure:
            #     A → B → D
            #         ↓   ↑
            #         C → E
            add_edge!(bn, :A, :B)
            add_edge!(bn, :B, :C)
            add_edge!(bn, :B, :D)
            add_edge!(bn, :C, :E)
            add_edge!(bn, :E, :D)

            @test is_conditionally_independent(bn, :A, :E, [:B, :C])
            @test !is_conditionally_independent(bn, :A, :E, Symbol[])
        end

        @testset "Error Handling" begin
            bn = BayesianNetwork{Symbol}()

            add_stochastic_vertex!(bn, :A, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(), false, :continuous)
            @test_throws KeyError is_conditionally_independent(bn, :A, :B, [:NonExistent])
        end
    end

    @testset "Conditional Independence (Single and Multiple Variables)" begin
        bn = BayesianNetwork{Symbol}()

        # Create a complex network
        #     A → B → D
        #     ↓   ↓   ↑
        #     C → E → F
        for v in [:A, :B, :C, :D, :E, :F]
            add_stochastic_vertex!(bn, v, Normal(), false, :continuous)
        end

        add_edge!(bn, :A, :B)
        add_edge!(bn, :A, :C)
        add_edge!(bn, :B, :D)
        add_edge!(bn, :B, :E)
        add_edge!(bn, :C, :E)
        add_edge!(bn, :E, :F)
        add_edge!(bn, :F, :D)

        # Test single variable independence
        @test is_conditionally_independent(bn, :A, :F, [:B, :C])
        @test !is_conditionally_independent(bn, :A, :D, Symbol[])

        # Test multiple variable independence
        @test is_conditionally_independent(bn, [:A], [:F], [:B, :C])
        @test is_conditionally_independent(bn, [:A, :B], [:F], [:C, :E])
        @test !is_conditionally_independent(bn, [:A, :B], [:D, :F], Symbol[])

        # Test when some variables are in conditioning set
        @test is_conditionally_independent(bn, [:A, :B], [:D, :F], [:A])
        @test is_conditionally_independent(bn, [:A, :B], [:D, :F], [:F])

        # Test error handling
        @test_throws KeyError is_conditionally_independent(
            bn, [:A, :NonExistent], [:F], [:B]
        )
        @test_throws KeyError is_conditionally_independent(
            bn, [:A], [:F, :NonExistent], [:B]
        )
        @test_throws KeyError is_conditionally_independent(bn, [:A], [:F], [:NonExistent])
        @test_throws ArgumentError is_conditionally_independent(bn, Symbol[], [:F], [:B])
        @test_throws ArgumentError is_conditionally_independent(bn, [:A], Symbol[], [:B])
    end
    @testset "Translating BUGSGraph to BayesianNetwork" begin
        # Define the test model using JuliaBUGS
        test_model = @bugs begin
            a ~ dnorm(0, 1)
            b ~ dnorm(0, 1)
            c ~ dnorm(0, 1)
        end

        inits = (a=1.0, b=2.0, c=3.0)

        model = compile(test_model, NamedTuple(), inits)

        g = model.g

        # Translate the BUGSGraph to a BayesianNetwork
        bn = translate_BUGSGraph_to_BayesianNetwork(g, model.evaluation_env)

        # Verify the translation
        @test length(bn.names) == 3
        @test bn.names_to_ids[VarName(:a)] == 1
        @test bn.names_to_ids[VarName(:b)] == 2
        @test bn.names_to_ids[VarName(:c)] == 3

        @test bn.is_stochastic[bn.names_to_ids[VarName(:a)]] == true
        @test bn.is_stochastic[bn.names_to_ids[VarName(:b)]] == true
        @test bn.is_stochastic[bn.names_to_ids[VarName(:c)]] == true

        @test bn.distributions[bn.names_to_ids[VarName(:a)]] isa Function
        @test bn.distributions[bn.names_to_ids[VarName(:b)]] isa Function
        @test bn.distributions[bn.names_to_ids[VarName(:c)]] isa Function
    end
    @testset "Translating Complex BUGSGraph to BayesianNetwork" begin
        # Define a more complex test model using JuliaBUGS
        complex_model = @bugs begin
            a ~ dnorm(0, 1)
            b ~ dnorm(1, 1)
            c = a + b
        end

        complex_inits = (a=1.0, b=2.0, c=3.0)

        complex_compiled_model = compile(complex_model, NamedTuple(), complex_inits)

        complex_g = complex_compiled_model.g

        # Translate the complex BUGSGraph to a BayesianNetwork
        complex_bn = translate_BUGSGraph_to_BayesianNetwork(
            complex_g, complex_compiled_model.evaluation_env
        )

        # Verify the translation
        @test length(complex_bn.names) == 3
        @test complex_bn.names_to_ids[VarName(:a)] == 1
        @test complex_bn.names_to_ids[VarName(:b)] == 2
        @test complex_bn.names_to_ids[VarName(:c)] == 3

        @test complex_bn.is_stochastic[complex_bn.names_to_ids[VarName(:a)]] == true
        @test complex_bn.is_stochastic[complex_bn.names_to_ids[VarName(:b)]] == true
        @test complex_bn.is_stochastic[complex_bn.names_to_ids[VarName(:c)]] == false

        @test complex_bn.distributions[complex_bn.names_to_ids[VarName(:a)]] isa Function
        @test complex_bn.distributions[complex_bn.names_to_ids[VarName(:b)]] isa Function
        @test complex_bn.deterministic_functions[complex_bn.names_to_ids[VarName(:c)]] isa
            Function
    end

    @testset "Evaluate function Evaluation" begin
        test_model = @bugs begin
            a ~ dnorm(0, 1)
            b ~ dnorm(0, 1)
            c ~ dnorm(0, 1)
        end

        inits = (a=1.0, b=2.0, c=3.0)

        model = compile(test_model, NamedTuple(), inits)

        g = model.g

        # Translate the BUGSGraph to a BayesianNetwork
        bn = translate_BUGSGraph_to_BayesianNetwork(g, model.evaluation_env)

        # Verify the translation
        @test length(bn.names) == 3
        @test bn.names_to_ids[VarName(:a)] == 1
        @test bn.names_to_ids[VarName(:b)] == 2
        @test bn.names_to_ids[VarName(:c)] == 3

        @test bn.is_stochastic[bn.names_to_ids[VarName(:a)]] == true
        @test bn.is_stochastic[bn.names_to_ids[VarName(:b)]] == true
        @test bn.is_stochastic[bn.names_to_ids[VarName(:c)]] == true

        @test bn.distributions[bn.names_to_ids[VarName(:a)]] isa Function
        @test bn.distributions[bn.names_to_ids[VarName(:b)]] isa Function
        @test bn.distributions[bn.names_to_ids[VarName(:c)]] isa Function
    end
    @testset "Translating Complex BUGSGraph to BayesianNetwork and Evaluate" begin
        # Define a more complex test model using JuliaBUGS
        complex_model = @bugs begin
            a ~ dnorm(0, 1)
            b ~ dnorm(1, 1)
            c = a + b
        end

        complex_inits = (a=1.0, b=2.0, c=3.0)

        complex_compiled_model = compile(complex_model, NamedTuple(), complex_inits)

        complex_g = complex_compiled_model.g

        # Translate the complex BUGSGraph to a BayesianNetwork
        complex_bn = translate_BUGSGraph_to_BayesianNetwork(
            complex_g, complex_compiled_model.evaluation_env
        )

        evaluation_env, logp = evaluate(complex_bn)

        @test haskey(evaluation_env, :a)
        @test haskey(evaluation_env, :b)
        @test haskey(evaluation_env, :c)
        @test evaluation_env[:c] ≈ evaluation_env[:a] + evaluation_env[:b]
        @test logp ≈
            logpdf(Normal(0, 1), evaluation_env[:a]) +
              logpdf(Normal(1, 1), evaluation_env[:b])
    end

    @testset "Translating Loop-based BUGSGraph to BayesianNetwork and Evaluate" begin
        # Adding a test model with a for loop
        loop_model = @bugs begin
            for i in 1:3
                x[i] ~ dnorm(i, 1)
            end
        end

        loop_inits = NamedTuple{(:x,)}(([1.0, 2.0, 3.0],))

        loop_compiled_model = compile(loop_model, NamedTuple(), loop_inits)

        loop_g = loop_compiled_model.g

        # Translate the loop-based BUGSGraph to a BayesianNetwork
        loop_bn = translate_BUGSGraph_to_BayesianNetwork(
            loop_g, loop_compiled_model.evaluation_env
        )

        loop_evaluation_env, loop_logp = evaluate(loop_bn)

        @test haskey(loop_evaluation_env, :x) && length(loop_evaluation_env[:x]) == 3
        @test loop_logp ≈ sum(logpdf(Normal(i, 1), loop_evaluation_env[:x][i]) for i in 1:3)
    end

    @testset "evaluate_with_values for BayesianNetwork" begin
        @testset "Loop model with Normal distributions" begin
            # Create model with a for loop
            loop_model = @bugs begin
                for i in 1:3
                    x[i] ~ dnorm(i, 1)
                end
            end

            loop_inits = NamedTuple{(:x,)}(([1.0, 2.0, 3.0],))
            loop_compiled_model = compile(loop_model, NamedTuple(), loop_inits)

            # Convert to BayesianNetwork
            loop_bn = translate_BUGSGraph_to_BayesianNetwork(
                loop_compiled_model.g, loop_compiled_model.evaluation_env
            )

            loop_params = rand(3)

            # Get result from our BayesianNetwork implementation
            bn_env, bn_logjoint = evaluate_with_values(loop_bn, loop_params)

            # Also verify against manual calculation
            manual_logjoint = sum(logpdf(Normal(i, 1), bn_env[:x][i]) for i in 1:3)
            @test bn_logjoint ≈ manual_logjoint rtol = 1E-6
        end

        @testset "Simple univariate model - corrected" begin
            model_def = @bugs begin
                mu ~ Normal(0, 10)
                sigma ~ Gamma(2, 3)
                y ~ Normal(mu, sqrt(sigma))
            end

            model = compile(model_def, NamedTuple())
            bn = translate_BUGSGraph_to_BayesianNetwork(model.g, model.evaluation_env)

            params = [1.5, 2.0, 3.0]

            # Get result from BUGSModel
            bugs_env, (bugs_logprior, bugs_loglikelihood, bugs_logjoint) = JuliaBUGS._tempered_evaluate!!(
                model, params; temperature=1.0
            )

            # Our implementation
            bn_env, bn_logjoint = evaluate_with_values(bn, params)

            # Manual calculation that matches BUGSModel
            # First parameter is sigma
            sigma_param = params[1]
            b_sigma = Bijectors.bijector(Gamma(2, 3))
            b_sigma_inv = Bijectors.inverse(b_sigma)
            sigma_reconstructed = JuliaBUGS.reconstruct(
                b_sigma_inv, Gamma(2, 3), [sigma_param]
            )
            sigma_val, sigma_logjac = Bijectors.with_logabsdet_jacobian(
                b_sigma_inv, sigma_reconstructed
            )
            sigma_logpdf = logpdf(Gamma(2, 3), sigma_val)

            # Second parameter is mu
            mu_param = params[2]
            mu_val = mu_param  # No transformation for Normal
            mu_logpdf = logpdf(Normal(0, 10), mu_val)

            # Third parameter is y
            y_param = params[3]
            y_val = y_param  # No transformation for Normal
            y_logpdf = logpdf(Normal(mu_val, sqrt(sigma_val)), y_val)

            # Sum them up in the right order
            manual_logprior = sigma_logpdf + sigma_logjac + mu_logpdf + y_logpdf

            # Tests
            @test manual_logprior ≈ bugs_logprior rtol = 1E-6
            @test bn_logjoint ≈ bugs_logjoint rtol = 1E-6
        end
    end

    @testset "BUGSModel vs BayesianNetwork Evaluation" begin
        @testset "Simple univariate model comparison" begin
            # Define model
            model_def = @bugs begin
                mu ~ Normal(0, 10)
                sigma ~ Gamma(2, 3)
                y ~ Normal(mu, sqrt(sigma))
            end

            # Compile BUGSModel
            bugs_model = compile(model_def, NamedTuple())

            # Convert to BayesianNetwork
            bn = translate_BUGSGraph_to_BayesianNetwork(
                bugs_model.g, bugs_model.evaluation_env
            )

            # Evaluate original BUGSModel
            bugs_env, bugs_logp = AbstractPPL.evaluate!!(bugs_model)

            # Evaluate BayesianNetwork
            bn_env, bn_logp = evaluate(bn)

            # Compare results
            @test bn_logp ≈ bugs_logp rtol = 1E-6

            # Check if all values match
            for name in bugs_model.flattened_graph_node_data.sorted_nodes
                @test AbstractPPL.get(bugs_env, name) ≈ AbstractPPL.get(bn_env, name) rtol =
                    1E-6
            end
        end

        @testset "Model with parameters comparison" begin
            # Define model
            model_def = @bugs begin
                mu ~ Normal(0, 10)
                sigma ~ Gamma(2, 3)
                y ~ Normal(mu, sqrt(sigma))
            end

            # Compile BUGSModel
            bugs_model = compile(model_def, NamedTuple())

            # Convert to BayesianNetwork
            bn = translate_BUGSGraph_to_BayesianNetwork(
                bugs_model.g, bugs_model.evaluation_env
            )

            # Create random parameters
            params = rand(3)

            # Evaluate BUGSModel with parameters
            bugs_env, (bugs_logprior, bugs_loglikelihood, bugs_logjoint) = JuliaBUGS._tempered_evaluate!!(
                bugs_model, params; temperature=1.0
            )

            # Evaluate BayesianNetwork with parameters
            bn_env, bn_logjoint = evaluate_with_values(bn, params)

            # Compare results
            @test bn_logjoint ≈ bugs_logjoint rtol = 1E-6

            # Check if all values match
            for name in bugs_model.flattened_graph_node_data.sorted_nodes
                @test AbstractPPL.get(bugs_env, name) ≈ AbstractPPL.get(bn_env, name) rtol =
                    1E-6
            end
        end

        @testset "Hierarchical model comparison" begin
            # Define a hierarchical model
            model_def = @bugs begin
                alpha ~ Normal(0, 1)
                beta ~ Normal(alpha, 1)
                gamma ~ Normal(beta, 1)
                x ~ Normal(gamma, 1)
            end

            # Compile BUGSModel
            bugs_model = compile(model_def, NamedTuple())

            # Convert to BayesianNetwork
            bn = translate_BUGSGraph_to_BayesianNetwork(
                bugs_model.g, bugs_model.evaluation_env
            )

            # Create random parameters
            params = rand(4)

            # Evaluate BUGSModel with parameters
            bugs_env, (bugs_logprior, bugs_loglikelihood, bugs_logjoint) = JuliaBUGS._tempered_evaluate!!(
                bugs_model, params; temperature=1.0
            )

            # Evaluate BayesianNetwork with parameters
            bn_env, bn_logjoint = evaluate_with_values(bn, params)

            # Compare results
            @test bn_logjoint ≈ bugs_logjoint rtol = 1E-6
        end
    end

    @testset "Marginalization for Discrete Variables" begin
        # Helper functions for common test operations
        """
        Set node types for specific variables without modifying the original BayesianNetwork.
        Returns a new BayesianNetwork with updated node_types.
        """
        function set_node_types(bn::BayesianNetwork{V,T,F}, var_types) where {V,T,F}
            new_node_types = copy(bn.node_types)

            for (var, type) in var_types
                id = bn.names_to_ids[var]
                new_node_types[id] = type
            end

            return BayesianNetwork(
                bn.graph,
                bn.names,
                bn.names_to_ids,
                bn.evaluation_env,
                bn.loop_vars,
                bn.distributions,
                bn.deterministic_functions,
                bn.stochastic_ids,
                bn.deterministic_ids,
                bn.is_stochastic,
                bn.is_observed,
                new_node_types,
                bn.transformed_var_lengths,
                bn.transformed_param_length,
            )
        end

        """
        Condition the BayesianNetwork on observed values.
        Returns a new BayesianNetwork with updated observation status and values.
        """
        function set_observations(bn::BayesianNetwork{V,T,F}, observations) where {V,T,F}
            new_is_observed = copy(bn.is_observed)
            new_evaluation_env = deepcopy(bn.evaluation_env)

            for (var, value) in observations
                id = bn.names_to_ids[var]
                new_is_observed[id] = true
                new_evaluation_env = BangBang.setindex!!(new_evaluation_env, value, var)
            end

            return BayesianNetwork(
                bn.graph,
                bn.names,
                bn.names_to_ids,
                new_evaluation_env,
                bn.loop_vars,
                bn.distributions,
                bn.deterministic_functions,
                bn.stochastic_ids,
                bn.deterministic_ids,
                bn.is_stochastic,
                new_is_observed,
                bn.node_types,
                bn.transformed_var_lengths,
                bn.transformed_param_length,
            )
        end

        """
        Helper function to get variables by name from a BayesianNetwork
        """
        function get_variables_by_name(bn, var_names)
            result = Dict{String,Any}()
            for var in bn.names
                var_str = string(var)
                if var_str in var_names
                    result[var_str] = var
                end
            end
            return result
        end

        """
        Helper function to run common test pattern for marginalization
        """
        function test_marginalization(
            bn, discrete_vars, observations, expected_logp; params=Float64[], rtol=1e-6
        )
            # Set node types for discrete variables
            bn = set_node_types(bn, discrete_vars)

            # Set observations
            bn = set_observations(bn, observations)

            # Run marginalization
            _, margin_logp = evaluate_with_marginalization(bn, params)

            # Test against expected result
            @test margin_logp ≈ expected_logp rtol = rtol

            return margin_logp
        end

        @testset "Simple Binary Discrete Models" begin
            @testset "Bernoulli → Normal model" begin
                # Create a simple model with Bernoulli → Normal structure
                model_def = @bugs begin
                    z ~ Bernoulli(0.3)

                    # Define mu and sigma based on z using explicit indicator variables
                    mu_z0 = 0.0
                    mu_z1 = 5.0
                    mu = mu_z0 * (1 - z) + mu_z1 * z

                    sigma_z0 = 1.0
                    sigma_z1 = 2.0
                    sigma = sigma_z0 * (1 - z) + sigma_z1 * z

                    y ~ Normal(mu, sigma)
                end

                # Compile and convert to BN
                compiled_model = compile(model_def, NamedTuple())
                bn = translate_BUGSGraph_to_BayesianNetwork(
                    compiled_model.g, compiled_model.evaluation_env
                )

                # Get variables
                vars = get_variables_by_name(bn, ["z", "y"])

                # Manual calculation for y=2.0
                y_value = 2.0
                p_z0 = 0.7  # 1 - 0.3
                p_z1 = 0.3
                p_y_given_z0 = pdf(Normal(0.0, 1.0), y_value)
                p_y_given_z1 = pdf(Normal(5.0, 2.0), y_value)
                manual_p_y = p_z0 * p_y_given_z0 + p_z1 * p_y_given_z1
                expected_logp = log(manual_p_y)

                # Run the test
                test_marginalization(
                    bn,
                    Dict(vars["z"] => :discrete),
                    Dict(vars["y"] => y_value),
                    expected_logp,
                )
            end

            @testset "X1 (continuous) → X2 (discrete) → X3 (continuous)" begin
                # Create model with continuous → discrete → continuous structure
                model_def = @bugs begin
                    # X1: Continuous uniform variable
                    x1 ~ Uniform(0, 1)

                    # X2: Discrete variable that depends on X1
                    x2 ~ Bernoulli(x1)

                    # X3: Continuous variable that depends on X2
                    mu_x2_0 = 2.0
                    mu_x2_1 = 10.0
                    mu = mu_x2_0 * (1 - x2) + mu_x2_1 * x2
                    sigma = 1.0
                    x3 ~ Normal(mu, sigma)
                end

                # Compile and convert to BN
                compiled_model = compile(model_def, NamedTuple())
                bn = translate_BUGSGraph_to_BayesianNetwork(
                    compiled_model.g, compiled_model.evaluation_env
                )

                # Get variables
                vars = get_variables_by_name(bn, ["x1", "x2", "x3"])

                # Helper for expected result calculation
                function calculate_expected_logp(x1_val, x3_val)
                    # Calculate prior probabilities for X2
                    p_x2_0 = 1 - x1_val  # P(X2=0|X1) = 1-X1
                    p_x2_1 = x1_val      # P(X2=1|X1) = X1

                    # Calculate likelihoods for X3 given X2
                    likelihood_x2_0 = pdf(Normal(2.0, 1.0), x3_val)
                    likelihood_x2_1 = pdf(Normal(10.0, 1.0), x3_val)

                    # Calculate joint probabilities
                    joint_x2_0 = p_x2_0 * likelihood_x2_0
                    joint_x2_1 = p_x2_1 * likelihood_x2_1

                    # Calculate marginal probability by summing over X2
                    marginal = joint_x2_0 + joint_x2_1

                    # Return log probability
                    return log(marginal)
                end

                # Test cases with different values
                test_cases = [
                    (0.7, 8.5),  # X1=0.7, X3=8.5
                    (0.3, 3.0),  # X1=0.3, X3=3.0
                    (0.7, 3.0),  # X1=0.7, X3=3.0
                    (0.3, 8.5),  # X1=0.3, X3=8.5
                ]

                for (x1_val, x3_val) in test_cases
                    # Calculate expected result
                    expected_logp = calculate_expected_logp(x1_val, x3_val)

                    # Run the test
                    @testset "X1=$x1_val, X3=$x3_val" begin
                        test_marginalization(
                            bn,
                            Dict(vars["x2"] => :discrete),
                            Dict(vars["x1"] => x1_val, vars["x3"] => x3_val),
                            expected_logp,
                        )
                    end
                end
            end
        end

        @testset "HMM and Complex Models" begin
            @testset "Marginalization with parameter values" begin
                # Create a model with both discrete and continuous variables
                model_def = @bugs begin
                    # Continuous variable - will use parameter value
                    x ~ Normal(0, 1)

                    # Discrete variable
                    z ~ Bernoulli(0.3)

                    # Observed variable that depends on both x and z
                    mu_z0 = x      # If z=0, mean is x
                    mu_z1 = x + 5  # If z=1, mean is x+5
                    mu = mu_z0 * (1 - z) + mu_z1 * z

                    sigma = 1.0
                    obs ~ Normal(mu, sigma)
                end

                # Compile and convert to BN
                compiled_model = compile(model_def, NamedTuple())
                bn = translate_BUGSGraph_to_BayesianNetwork(
                    compiled_model.g, compiled_model.evaluation_env
                )

                # Get variables
                vars = get_variables_by_name(bn, ["x", "z", "obs"])

                # Set observations and discrete variable
                obs_value = 2.5
                x_param = 1.0

                # Helper for expected result calculation
                function calculate_expected_logp(x_param, obs_value)
                    # Prior probabilities for z
                    p_z0 = 0.7  # 1 - 0.3
                    p_z1 = 0.3

                    # Prior for x
                    x_logprior = logpdf(Normal(0, 1), x_param)

                    # Likelihood for z=0: P(obs|x,z=0)
                    z0_likelihood = logpdf(Normal(x_param, 1.0), obs_value)

                    # Likelihood for z=1: P(obs|x,z=1)
                    z1_likelihood = logpdf(Normal(x_param + 5, 1.0), obs_value)

                    # Joint probabilities: P(x,z,obs) = P(x) * P(z) * P(obs|x,z)
                    z0_joint = x_logprior + log(p_z0) + z0_likelihood
                    z1_joint = x_logprior + log(p_z1) + z1_likelihood

                    # Marginalize: P(x,obs) = sum_z P(x,z,obs)
                    return log(exp(z0_joint) + exp(z1_joint))
                end

                # Calculate expected result
                expected_logp = calculate_expected_logp(x_param, obs_value)

                # Run the test with parameters
                test_marginalization(
                    bn,
                    Dict(vars["z"] => :discrete),
                    Dict(vars["obs"] => obs_value),
                    expected_logp;
                    params=[x_param],
                    rtol=0.1,
                )
            end
        end
    end
end
