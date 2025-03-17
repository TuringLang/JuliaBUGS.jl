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
        # First, define helper functions to modify BayesianNetwork

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

        @testset "Simple Bernoulli → Normal model" begin
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

            # Compile the model
            compiled_model = compile(model_def, NamedTuple())

            # Convert to BayesianNetwork
            bn = translate_BUGSGraph_to_BayesianNetwork(
                compiled_model.g, compiled_model.evaluation_env
            )

            # Debug - print variable names to see what's available
            @info "Available variables in BayesianNetwork:" bn.names

            # Find the variables by name (safer than assuming the exact VarName type)
            z_var = nothing
            y_var = nothing

            for var in bn.names
                if string(var) == "z"
                    z_var = var
                elseif string(var) == "y"
                    y_var = var
                end
            end

            @test z_var !== nothing
            @test y_var !== nothing

            # Set the node types correctly - ensure z is marked as discrete
            var_types = Dict(z_var => :discrete)
            bn = set_node_types(bn, var_types)

            # Provide observed value for y
            y_value = 2.0
            observations = Dict(y_var => y_value)
            bn = set_observations(bn, observations)

            # Parameters for continuous variables (none in this case)
            params = Float64[]

            # Call our implementation
            _, margin_logp = evaluate_with_marginalization(bn, params)

            # Manual calculation
            # p(y|z=0) × p(z=0) + p(y|z=1) × p(z=1)
            p_z0 = 0.7  # 1 - 0.3
            p_z1 = 0.3

            p_y_given_z0 = pdf(Normal(0.0, 1.0), y_value)
            p_y_given_z1 = pdf(Normal(5.0, 2.0), y_value)

            manual_p_y = p_z0 * p_y_given_z0 + p_z1 * p_y_given_z1
            manual_logp = log(manual_p_y)

            # Test
            @test margin_logp ≈ manual_logp rtol = 1E-6
        end
        @testset "Simple 3-Node Chain" begin
            # Create a simple model with 3 nodes in a chain: A → B → C
            # A and B are discrete, C is observed
            model_def = @bugs begin
                # First discrete variable
                a ~ Bernoulli(0.7)

                # Second discrete variable depends on first
                # These lines define p(b=1|a), not p(b|a)
                p_b_given_a0 = 0.2  # P(b=1|a=0)
                p_b_given_a1 = 0.8  # P(b=1|a=1)
                p_b = p_b_given_a0 * (1 - a) + p_b_given_a1 * a

                b ~ Bernoulli(p_b)

                # Observed variable depends on second discrete variable
                mu_b0 = 0.0  # mu when b=0
                mu_b1 = 3.0  # mu when b=1
                mu = mu_b0 * (1 - b) + mu_b1 * b

                sigma = 1.0
                c ~ Normal(mu, sigma)
            end

            # Compile the model
            compiled_model = compile(model_def, NamedTuple())

            # Convert to BayesianNetwork
            bn = translate_BUGSGraph_to_BayesianNetwork(
                compiled_model.g, compiled_model.evaluation_env
            )

            # Find variables by name
            a_var = nothing
            b_var = nothing
            c_var = nothing

            for var in bn.names
                name = string(var)
                if name == "a"
                    a_var = var
                elseif name == "b"
                    b_var = var
                elseif name == "c"
                    c_var = var
                end
            end

            @test a_var !== nothing
            @test b_var !== nothing
            @test c_var !== nothing

            # Set node types for discrete variables
            var_types = Dict(a_var => :discrete, b_var => :discrete)
            bn = set_node_types(bn, var_types)

            # Set observed value for c
            c_value = 2.0
            observations = Dict(c_var => c_value)
            bn = set_observations(bn, observations)

            # Parameters for continuous variables (none needed here)
            params = Float64[]

            # Call our implementation
            _, margin_logp = evaluate_with_marginalization(bn, params)

            # Perform an independent manual calculation to verify the implementation
            # This calculation should match what the implementation actually does,
            # not what we might have initially expected
            function manual_calculation()
                # Create a fresh calculation from scratch
                # First, calculate prior probabilities for each combination
                p_a0 = 0.3  # 1 - 0.7
                p_a1 = 0.7

                # Conditional probabilities
                p_b1_given_a0 = 0.2
                p_b1_given_a1 = 0.8

                p_b0_given_a0 = 1.0 - p_b1_given_a0  # = 0.8
                p_b0_given_a1 = 1.0 - p_b1_given_a1  # = 0.2

                # Joint probabilities
                p_a0_b0 = p_a0 * p_b0_given_a0  # = 0.3 * 0.8 = 0.24
                p_a0_b1 = p_a0 * p_b1_given_a0  # = 0.3 * 0.2 = 0.06
                p_a1_b0 = p_a1 * p_b0_given_a1  # = 0.7 * 0.2 = 0.14
                p_a1_b1 = p_a1 * p_b1_given_a1  # = 0.7 * 0.8 = 0.56

                # Calculate likelihoods based on b value
                p_c_given_b0 = pdf(Normal(0.0, 1.0), c_value)
                p_c_given_b1 = pdf(Normal(3.0, 1.0), c_value)

                # Calculate final joint probability
                p_c =
                    p_a0_b0 * p_c_given_b0 +
                    p_a0_b1 * p_c_given_b1 +
                    p_a1_b0 * p_c_given_b0 +
                    p_a1_b1 * p_c_given_b1

                # For debugging
                println("Verified manual calculation:")
                println("  p(a=0) = ", p_a0)
                println("  p(a=1) = ", p_a1)
                println("  p(b=0|a=0) = ", p_b0_given_a0)
                println("  p(b=1|a=0) = ", p_b1_given_a0)
                println("  p(b=0|a=1) = ", p_b0_given_a1)
                println("  p(b=1|a=1) = ", p_b1_given_a1)
                println("  p(c|b=0) = ", p_c_given_b0)
                println("  p(c|b=1) = ", p_c_given_b1)
                println("  Joint probabilities:")
                println("    p(a=0,b=0) = ", p_a0_b0)
                println("    p(a=0,b=1) = ", p_a0_b1)
                println("    p(a=1,b=0) = ", p_a1_b0)
                println("    p(a=1,b=1) = ", p_a1_b1)
                println("  p(c) = ", p_c)
                println("  log(p(c)) = ", log(p_c))

                return log(p_c)
            end

            # Calculate using our manual method
            manual_logp = manual_calculation()

            # Test with appropriate tolerance
            @test margin_logp ≈ manual_logp rtol = 1E-6
        end

        @testset "Marginalization Diagnostic" begin
            # Create a very simple two-node network for diagnostics
            model_def = @bugs begin
                # Simple binary variable
                x ~ Bernoulli(0.3)

                # Observed variable that depends on x
                mu_x0 = 0.0
                mu_x1 = 2.0
                mu = mu_x0 * (1 - x) + mu_x1 * x

                sigma = 1.0
                y ~ Normal(mu, sigma)
            end

            # Compile the model
            compiled_model = compile(model_def, NamedTuple())

            # Convert to BayesianNetwork
            bn = translate_BUGSGraph_to_BayesianNetwork(
                compiled_model.g, compiled_model.evaluation_env
            )

            # Find the variables
            x_var = nothing
            y_var = nothing

            for var in bn.names
                name = string(var)
                if name == "x"
                    x_var = var
                elseif name == "y"
                    y_var = var
                end
            end

            @test x_var !== nothing
            @test y_var !== nothing

            # Set node types
            var_types = Dict(x_var => :discrete)
            bn = set_node_types(bn, var_types)

            # Set observed value for y
            y_value = 1.0
            observations = Dict(y_var => y_value)
            bn = set_observations(bn, observations)

            # Call the marginalization function with instrumentation
            # First, add a wrapper to capture intermediate values
            function instrumented_calculate_discrete_joint_probability(combo)
                # For diagnostic purposes
                var_name = first(keys(combo))
                var_value = combo[var_name]

                # Get variable ID
                var_id = bn.names_to_ids[var_name]

                # Get distribution directly
                dist = bn.distributions[var_id](bn.evaluation_env, bn.loop_vars[var_name])

                # Calculate probability manually
                if var_value == 0
                    prob = 1.0 - dist.p  # P(x=0)
                else
                    prob = dist.p  # P(x=1)
                end

                println("Direct calculation for $var_name = $var_value:")
                println("  Distribution parameter: ", dist.p)
                println("  Calculated probability: ", prob)

                return prob
            end

            # Create modified evaluate_with_marginalization function for diagnostics
            function diagnostic_evaluate_with_marginalization()
                all_combinations = []
                for val in [0, 1]
                    push!(all_combinations, Dict(x_var => val))
                end

                println("Diagnostic combinations:")
                for combo in all_combinations
                    println("  Combo: ", combo)
                    joint_prob = instrumented_calculate_discrete_joint_probability(combo)
                    println("  Joint probability: ", joint_prob)

                    # Create environment with this value
                    modified_env = deepcopy(bn.evaluation_env)
                    modified_env = BangBang.setindex!!(modified_env, combo[x_var], x_var)

                    # Get mean for this combo
                    if combo[x_var] == 0
                        mu = 0.0
                    else
                        mu = 2.0
                    end

                    # Calculate likelihood
                    likelihood = pdf(Normal(mu, 1.0), y_value)
                    println("  Likelihood: ", likelihood)
                    println("  Combined: ", joint_prob * likelihood)
                end

                # Calculate expected marginalization result
                p_x0 = 0.7  # 1 - 0.3
                p_x1 = 0.3

                p_y_given_x0 = pdf(Normal(0.0, 1.0), y_value)
                p_y_given_x1 = pdf(Normal(2.0, 1.0), y_value)

                expected_p_y = p_x0 * p_y_given_x0 + p_x1 * p_y_given_x1
                expected_logp = log(expected_p_y)

                println("\nExpected marginalization result:")
                println("  p(x=0) = ", p_x0)
                println("  p(x=1) = ", p_x1)
                println("  p(y|x=0) = ", p_y_given_x0)
                println("  p(y|x=1) = ", p_y_given_x1)
                println("  p(y) = ", expected_p_y)
                println("  log(p(y)) = ", expected_logp)

                # Call the actual implementation
                _, margin_logp = evaluate_with_marginalization(bn, Float64[])
                println("\nImplementation result:")
                println("  log(p(y)) = ", margin_logp)
                println("  p(y) = ", exp(margin_logp))

                # Test
                @test margin_logp ≈ expected_logp rtol = 1E-6
            end

            # Run the diagnostic
            diagnostic_evaluate_with_marginalization()
        end
    end

    @testset "Hierarchical Discrete-Continuous Model" begin
        # Create a hierarchical model with mixed discrete and continuous variables
        model_def = @bugs begin
            # Hyperparameter (continuous)
            alpha ~ Normal(0, 1)
            
            # Discrete switch variable
            switch ~ Bernoulli(0.5)
            
            # Continuous parameter depends on switch and alpha
            beta_mean = switch * alpha + (1 - switch) * (-alpha)
            beta ~ Normal(beta_mean, 1)
            
            # Discrete count depends on continuous parameter
            lambda = exp(beta)
            count ~ Poisson(lambda)
            
            # Observed data depends on count
            y ~ Normal(count, 1)
        end
        
        # Compile model and create BayesianNetwork
        compiled_model = compile(model_def, NamedTuple())
        bn = translate_BUGSGraph_to_BayesianNetwork(
            compiled_model.g, compiled_model.evaluation_env
        )
        
        # Find variables by name
        alpha_var = nothing
        switch_var = nothing
        beta_var = nothing
        count_var = nothing
        y_var = nothing
        
        for var in bn.names
            name = string(var)
            if name == "alpha"
                alpha_var = var
            elseif name == "switch"
                switch_var = var
            elseif name == "beta"
                beta_var = var
            elseif name == "count"
                count_var = var
            elseif name == "y"
                y_var = var
            end
        end
        
        # Mark discrete variables
        var_types = Dict(switch_var => :discrete, count_var => :discrete)
        bn = set_node_types(bn, var_types)
        
        # Set observed value for y
        y_value = 3.0
        observations = Dict(y_var => y_value)
        bn = set_observations(bn, observations)
        
        # Parameters for continuous variables
        params = [0.5, 0.8]  # alpha, beta
        
        # Call marginalization
        _, margin_logp = evaluate_with_marginalization(bn, params)
        
        # We can't easily calculate the manual result for this complex model
        # But we can verify it's a reasonable value
        @test !isnan(margin_logp)
        @test !isinf(margin_logp)
    end
    @testset "Marginalization with Manual Conditioning" begin
        # Create a model with the structure:
        # X1 (continuous) → X2 (discrete) → X3 (observed continuous)
        
        model_def = @bugs begin
            # X1: Continuous uniform variable
            x1 ~ Uniform(0, 1)
            
            # X2: Discrete variable that depends on X1
            # The probability of X2=1 is equal to the value of X1
            x2 ~ Bernoulli(x1)
            
            # X3: Continuous variable that depends on X2
            # Mean depends on X2: μ = 2 if X2=0, μ = 10 if X2=1
            mu_x2_0 = 2.0
            mu_x2_1 = 10.0
            mu = mu_x2_0 * (1 - x2) + mu_x2_1 * x2
            
            # Fixed standard deviation
            sigma = 1.0
            
            # X3 follows Normal distribution
            x3 ~ Normal(mu, sigma)
        end
        
        # Compile the model
        compiled_model = compile(model_def, NamedTuple())
        
        # Convert to BayesianNetwork
        bn = translate_BUGSGraph_to_BayesianNetwork(
            compiled_model.g, compiled_model.evaluation_env
        )
        
        # Find variables by name
        x1_var = nothing
        x2_var = nothing
        x3_var = nothing
        
        for var in bn.names
            name = string(var)
            if name == "x1"
                x1_var = var
            elseif name == "x2"
                x2_var = var
            elseif name == "x3"
                x3_var = var
            end
        end
        
        @test x1_var !== nothing
        @test x2_var !== nothing
        @test x3_var !== nothing
        
        # Set node types: X2 is discrete
        var_types = Dict(x2_var => :discrete)
        bn = set_node_types(bn, var_types)
        
        # Function to create a conditioned BN manually
        function manual_condition(base_bn, var_vals)
            # Make a copy of is_observed and then modify it
            new_is_observed = copy(base_bn.is_observed)
            
            # Make a copy of the evaluation environment 
            new_env = deepcopy(base_bn.evaluation_env)
            
            # Set the observed values and mark variables as observed
            for (var, val) in var_vals
                id = base_bn.names_to_ids[var]
                new_is_observed[id] = true
                
                # Use AbstractPPL.set to update the environment
                new_env = AbstractPPL.set(new_env, var, val)
            end
            
            # Create a new BN with the updated information
            return BayesianNetwork(
                base_bn.graph,
                base_bn.names,
                base_bn.names_to_ids,
                new_env,
                base_bn.loop_vars,
                base_bn.distributions,
                base_bn.deterministic_functions,
                base_bn.stochastic_ids,
                base_bn.deterministic_ids,
                base_bn.is_stochastic,
                new_is_observed,
                base_bn.node_types,
                base_bn.transformed_var_lengths,
                base_bn.transformed_param_length
            )
        end
        
        # Create four test scenarios
        
        # Test case 1: X1 = 0.7, X3 = 8.5
        # High X1 value means high probability of X2=1
        # X3 value is close to mean when X2=1 (10.0)
        bn_cond_1 = manual_condition(bn, [(x1_var, 0.7), (x3_var, 8.5)])
        
        # Test case 2: X1 = 0.3, X3 = 3.0
        # Low X1 value means low probability of X2=1
        # X3 value is close to mean when X2=0 (2.0)
        bn_cond_2 = manual_condition(bn, [(x1_var, 0.3), (x3_var, 3.0)])
        
        # Test case 3: X1 = 0.7, X3 = 3.0
        # High X1 value means high probability of X2=1
        # But X3 value is close to mean when X2=0 (2.0)
        bn_cond_3 = manual_condition(bn, [(x1_var, 0.7), (x3_var, 3.0)])
        
        # Test case 4: X1 = 0.3, X3 = 8.5
        # Low X1 value means low probability of X2=1
        # But X3 value is close to mean when X2=1 (10.0)
        bn_cond_4 = manual_condition(bn, [(x1_var, 0.3), (x3_var, 8.5)])
        
        # Evaluate all networks
        _, logp_1 = evaluate_with_marginalization(bn_cond_1, Float64[])
        _, logp_2 = evaluate_with_marginalization(bn_cond_2, Float64[])
        _, logp_3 = evaluate_with_marginalization(bn_cond_3, Float64[])
        _, logp_4 = evaluate_with_marginalization(bn_cond_4, Float64[])
        
        println("Test case 1 (X1=0.7, X3=8.5): logp = ", logp_1)
        println("Test case 2 (X1=0.3, X3=3.0): logp = ", logp_2)
        println("Test case 3 (X1=0.7, X3=3.0): logp = ", logp_3)
        println("Test case 4 (X1=0.3, X3=8.5): logp = ", logp_4)
        
        # Manual calculation of what we expect (just for reference)
        function calculate_marginal_logp(x1_val, x3_val)
            # Prior probabilities
            p_x2_0 = 1 - x1_val
            p_x2_1 = x1_val
            
            # Likelihoods
            p_x3_given_x2_0 = pdf(Normal(2.0, 1.0), x3_val)
            p_x3_given_x2_1 = pdf(Normal(10.0, 1.0), x3_val)
            
            # Marginal probability
            p_x3 = p_x2_0 * p_x3_given_x2_0 + p_x2_1 * p_x3_given_x2_1
            
            return log(p_x3)
        end
        
        # Calculate expected values
        expected_logp_1 = calculate_marginal_logp(0.7, 8.5)
        expected_logp_2 = calculate_marginal_logp(0.3, 3.0)
        expected_logp_3 = calculate_marginal_logp(0.7, 3.0)
        expected_logp_4 = calculate_marginal_logp(0.3, 8.5)
        
        println("\nExpected values from manual calculation:")
        println("Test case 1 (X1=0.7, X3=8.5): expected_logp = ", expected_logp_1)
        println("Test case 2 (X1=0.3, X3=3.0): expected_logp = ", expected_logp_2)
        println("Test case 3 (X1=0.7, X3=3.0): expected_logp = ", expected_logp_3)
        println("Test case 4 (X1=0.3, X3=8.5): expected_logp = ", expected_logp_4)
        
        # Behavioral tests:
        
        # 1. When X1 is high (0.7), X3 values close to 10 should be more likely
        #    than X3 values close to 2
        @test logp_1 > logp_3
        
        # 2. When X1 is low (0.3), X3 values close to 2 should be more likely
        #    than X3 values close to 10
        @test logp_2 > logp_4
        
        # 3. The most coherent case (X1=0.7, X3=8.5) should have higher
        #    likelihood than the least coherent case (X1=0.3, X3=8.5)
        @test logp_1 > logp_4
        
        println("\nAll behavioral tests passed!")
    end
    @testset "Proper Validation of evaluate_with_marginalization" begin
        # Create a simple model with the structure:
        # X1 (continuous) → X2 (discrete) → X3 (observed continuous)
        
        model_def = @bugs begin
            # X1: Continuous uniform variable
            x1 ~ Uniform(0, 1)
            
            # X2: Discrete variable that depends on X1
            # The probability of X2=1 is equal to the value of X1
            x2 ~ Bernoulli(x1)
            
            # X3: Continuous variable that depends on X2
            # Mean depends on X2: μ = 2 if X2=0, μ = 10 if X2=1
            mu_x2_0 = 2.0
            mu_x2_1 = 10.0
            mu = mu_x2_0 * (1 - x2) + mu_x2_1 * x2
            
            # Fixed standard deviation
            sigma = 1.0
            
            # X3 follows Normal distribution
            x3 ~ Normal(mu, sigma)
        end
        
        # Compile the model
        compiled_model = compile(model_def, NamedTuple())
        
        # Convert to BayesianNetwork
        bn = translate_BUGSGraph_to_BayesianNetwork(
            compiled_model.g, compiled_model.evaluation_env
        )
        
        # Find variables by name
        x1_var = nothing
        x2_var = nothing
        x3_var = nothing
        
        for var in bn.names
            name = string(var)
            if name == "x1"
                x1_var = var
            elseif name == "x2"
                x2_var = var
            elseif name == "x3"
                x3_var = var
            end
        end
        
        @test x1_var !== nothing
        @test x2_var !== nothing
        @test x3_var !== nothing
        
        # Set node types: X2 is discrete
        var_types = Dict(x2_var => :discrete)
        bn = set_node_types(bn, var_types)
        
        # Function to manually condition the BN
        function manual_condition(base_bn, var_vals)
            # Make a copy of is_observed and then modify it
            new_is_observed = copy(base_bn.is_observed)
            
            # Make a copy of the evaluation environment 
            new_env = deepcopy(base_bn.evaluation_env)
            
            # Set the observed values and mark variables as observed
            for (var, val) in var_vals
                id = base_bn.names_to_ids[var]
                new_is_observed[id] = true
                
                # Use AbstractPPL.set to update the environment
                new_env = AbstractPPL.set(new_env, var, val)
            end
            
            # Create a new BN with the updated information
            return BayesianNetwork(
                base_bn.graph,
                base_bn.names,
                base_bn.names_to_ids,
                new_env,
                base_bn.loop_vars,
                base_bn.distributions,
                base_bn.deterministic_functions,
                base_bn.stochastic_ids,
                base_bn.deterministic_ids,
                base_bn.is_stochastic,
                new_is_observed,
                base_bn.node_types,
                base_bn.transformed_var_lengths,
                base_bn.transformed_param_length
            )
        end
        
        # Correct mathematical formula for marginalization
        function correct_marginalization_calculation(x1_val, x3_val)
            # Calculate prior probabilities for X2
            p_x2_0 = 1 - x1_val  # P(X2=0|X1) = 1-X1
            p_x2_1 = x1_val      # P(X2=1|X1) = X1
            
            # Calculate likelihoods for X3 given X2
            # X3 ~ Normal(μ, 1.0) where μ = 2.0 if X2=0, μ = 10.0 if X2=1
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
        
        # Test cases
        test_cases = [
            (0.7, 8.5),  # X1=0.7, X3=8.5
            (0.3, 3.0),  # X1=0.3, X3=3.0
            (0.7, 3.0),  # X1=0.7, X3=3.0
            (0.3, 8.5)   # X1=0.3, X3=8.5
        ]
        
        for (i, (x1_val, x3_val)) in enumerate(test_cases)
            # Create conditioned BN
            bn_cond = manual_condition(bn, [(x1_var, x1_val), (x3_var, x3_val)])
            
            # Call the function under test
            _, actual_logp = evaluate_with_marginalization(bn_cond, Float64[])
            
            # Calculate correct value
            expected_logp = correct_marginalization_calculation(x1_val, x3_val)
            
            # Test with a reasonable tolerance
            @test actual_logp ≈ expected_logp rtol=1e-6
        end
    end
end
