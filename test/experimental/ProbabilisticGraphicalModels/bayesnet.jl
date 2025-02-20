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
    evaluate
using BangBang
#using MetaGraphsNext
using JuliaBUGS: @bugs, compile, NodeInfo, VarName
using Bijectors: Bijectors

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
        @test !haskey(bn_decond.evaluation_env, :A)
        @test bn_decond.evaluation_env[:B] == 2.0
    
        # Ensure bn_cond2 is not mutated
        @test bn_cond2.is_observed[1] == true
        @test bn_cond2.evaluation_env[:A] == 1.0
    
        # Test deconditioning all
        bn_decond_all = decondition(bn_cond2)
        @test all(.!bn_decond_all.is_observed)
        @test isempty(bn_decond_all.evaluation_env)  # NamedTuple should now be empty
    
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
        bn = BayesianNetwork{Symbol}()

        # Add stochastic vertices
        add_stochastic_vertex!(bn, :A, () -> Normal(0, 1), false, :continuous)
        add_stochastic_vertex!(bn, :B, () -> Normal(1, 1 / sqrt(2)), false, :continuous)

        # Add deterministic vertex C = A + B
        add_deterministic_vertex!(bn, :C, (a, b) -> a + b)
        add_edge!(bn, :A, :C)
        add_edge!(bn, :B, :C)

        # Set values for the stochastic nodes
        new_values = deepcopy(bn.values)
        new_values = BangBang.setindex!!(new_values, 0.5, :A)
        new_values = BangBang.setindex!!(new_values, 1.5, :B)

        # Create a new BayesianNetwork instance with updated values
        bn = BayesianNetwork(
            bn.graph,
            bn.names,
            bn.names_to_ids,
            new_values,
            bn.distributions,
            bn.deterministic_functions,
            bn.stochastic_ids,
            bn.deterministic_ids,
            bn.is_stochastic,
            bn.is_observed,
            bn.node_types,
        )

        # Evaluate the Bayesian Network
        evaluation_env, logp = evaluate(bn)

        # Verify the evaluation
        @test haskey(evaluation_env, :A)
        @test haskey(evaluation_env, :B)
        @test haskey(evaluation_env, :C)
        @test evaluation_env[:A] == 0.5
        @test evaluation_env[:B] == 1.5
        @test evaluation_env[:C] == 2.0
        @test logp isa Float64
        @test logp ≈ logpdf(Normal(0, 1), 0.5) + logpdf(Normal(1, 1 / sqrt(2)), 1.5)
    end

    @testset "Multiplicative network Evaluation" begin
        bn3 = BayesianNetwork{Symbol}()

        add_stochastic_vertex!(bn3, :A, () -> Normal(2, 1), false, :continuous)
        add_stochastic_vertex!(bn3, :B, () -> Normal(3, 1), false, :continuous)
        add_deterministic_vertex!(bn3, :C, (a, b) -> a * b)
        add_edge!(bn3, :A, :C)
        add_edge!(bn3, :B, :C)

        # Set specific values; for example, A = 2.5, B = 2.8, so C = 2.5*2.8 = 7.0.
        new_values3 = deepcopy(bn3.values)
        new_values3 = BangBang.setindex!!(new_values3, 2.5, :A)
        new_values3 = BangBang.setindex!!(new_values3, 2.8, :B)
        bn3 = BayesianNetwork(
            bn3.graph,
            bn3.names,
            bn3.names_to_ids,
            new_values3,
            bn3.distributions,
            bn3.deterministic_functions,
            bn3.stochastic_ids,
            bn3.deterministic_ids,
            bn3.is_stochastic,
            bn3.is_observed,
            bn3.node_types,
        )

        env3, logp3 = evaluate(bn3)
        expected_logp3 = logpdf(Normal(2, 1), 2.5) + logpdf(Normal(3, 1), 2.8)

        @test env3[:A] == 2.5
        @test env3[:B] == 2.8
        @test env3[:C] == 7.0
        @test logp3 ≈ expected_logp3 atol = 1e-4
    end

    @testset "Discrete Bayesian Network Evaluation" begin
        bn_disc = BayesianNetwork{Symbol}()

        # Add discrete stochastic vertices.
        # For a discrete variable, the provided function returns a distribution.
        add_stochastic_vertex!(bn_disc, :A, () -> Bernoulli(0.5), false, :discrete)
        add_stochastic_vertex!(bn_disc, :B, () -> Bernoulli(0.7), false, :discrete)

        # Deterministic node C = A + B.
        add_deterministic_vertex!(bn_disc, :C, (a, b) -> a + b)
        add_edge!(bn_disc, :A, :C)
        add_edge!(bn_disc, :B, :C)

        # Set values: A = 1, B = 0.
        new_values_disc = deepcopy(bn_disc.values)
        new_values_disc = BangBang.setindex!!(new_values_disc, 1, :A)
        new_values_disc = BangBang.setindex!!(new_values_disc, 0, :B)
        bn_disc = BayesianNetwork(
            bn_disc.graph,
            bn_disc.names,
            bn_disc.names_to_ids,
            new_values_disc,
            bn_disc.distributions,
            bn_disc.deterministic_functions,
            bn_disc.stochastic_ids,
            bn_disc.deterministic_ids,
            bn_disc.is_stochastic,
            bn_disc.is_observed,
            bn_disc.node_types,
        )

        # Evaluate the discrete network.
        env_disc, logp_disc = evaluate(bn_disc)

        # Expected log probability:
        expected_logp_disc = logpdf(Bernoulli(0.5), 1) + logpdf(Bernoulli(0.7), 0)
        @test haskey(env_disc, :A)
        @test haskey(env_disc, :B)
        @test haskey(env_disc, :C)
        @test env_disc[:A] == 1
        @test env_disc[:B] == 0
        @test env_disc[:C] == 1
        @test logp_disc ≈ expected_logp_disc atol = 1e-4
    end

    @testset "Simpler Mixture Bayesian Network Test" begin
        # Create a new Bayesian network.
        bn = BayesianNetwork{Symbol}()

        # Add a discrete indicator node I ~ Bernoulli(0.3)
        add_stochastic_vertex!(bn, :I, () -> Bernoulli(0.3), false, :discrete)

        # Add a continuous node X whose distribution depends on I.
        # If I == 1 then X ~ Normal(2, 1); if I == 0 then X ~ Normal(-2, 1).
        # Here we directly provide a function that accepts parent values.
        add_stochastic_vertex!(
            bn, :X, (parent_vals...) -> begin
                if parent_vals[1] == 1
                    return Normal(2, 1)
                else
                    return Normal(-2, 1)
                end
            end, false, :continuous
        )

        # Record the dependency: I is a parent of X.
        add_edge!(bn, :I, :X)

        # (No deterministic node in this simplified test case.)

        # Set specific values for I and X.
        # For example, let I = 1 (so that X follows Normal(2,1)) and X = 2.5.
        new_values = deepcopy(bn.values)
        new_values = BangBang.setindex!!(new_values, 1, :I)
        new_values = BangBang.setindex!!(new_values, 2.5, :X)
        bn = BayesianNetwork(
            bn.graph,
            bn.names,
            bn.names_to_ids,
            new_values,
            bn.distributions,
            bn.deterministic_functions,  # likely empty here
            bn.stochastic_ids,
            bn.deterministic_ids,
            bn.is_stochastic,
            bn.is_observed,
            bn.node_types,
        )

        # Evaluate the network.
        env, logp = evaluate(bn)

        # Expected log probability:
        # For I: logpdf(Bernoulli(0.3), 1)
        # For X: since I == 1, use Normal(2,1): logpdf(Normal(2, 1), 2.5)
        expected_logp = logpdf(Bernoulli(0.3), 1) + logpdf(Normal(2, 1), 2.5)

        @test haskey(env, :I)
        @test haskey(env, :X)
        @test env[:I] == 1
        @test env[:X] == 2.5
        @test logp ≈ expected_logp atol = 1e-4
        println("Simpler Mixture Network Log probability: ", logp)
    end
    @testset "Mixture Bayesian Network with Deterministic Node" begin
        # Create a new Bayesian network.
        bn = BayesianNetwork{Symbol}()

        # Add a discrete indicator node I ~ Bernoulli(0.3)
        add_stochastic_vertex!(bn, :I, () -> Bernoulli(0.3), false, :discrete)

        # Add a continuous node X whose distribution depends on I.
        # If I == 1 then X ~ Normal(2, 1); if I == 0 then X ~ Normal(-2, 1).
        # We directly supply a function that accepts parent values.
        add_stochastic_vertex!(
            bn, :X, (parent_vals...) -> begin
                if parent_vals[1] == 1
                    return Normal(2, 1)
                else
                    return Normal(-2, 1)
                end
            end, false, :continuous
        )

        # Record the dependency: I is a parent of X.
        add_edge!(bn, :I, :X)

        # Add a deterministic node Y = X + 1.
        add_deterministic_vertex!(bn, :Y, x -> x + 1)
        add_edge!(bn, :X, :Y)

        # Set specific values for I and X.
        # For example, let I = 1 (so that X follows Normal(2,1)) and X = 2.5.
        # Then Y should equal 2.5 + 1 = 3.5.
        new_values = deepcopy(bn.values)
        new_values = BangBang.setindex!!(new_values, 1, :I)
        new_values = BangBang.setindex!!(new_values, 2.5, :X)
        bn = BayesianNetwork(
            bn.graph,
            bn.names,
            bn.names_to_ids,
            new_values,
            bn.distributions,
            bn.deterministic_functions,  # now includes the function for Y
            bn.stochastic_ids,
            bn.deterministic_ids,
            bn.is_stochastic,
            bn.is_observed,
            bn.node_types,
        )

        # Evaluate the network.
        env, logp = evaluate(bn)

        # Expected log probability:
        # For I: logpdf(Bernoulli(0.3), 1)
        # For X: since I == 1, we use Normal(2,1): logpdf(Normal(2,1), 2.5)
        # (The deterministic node Y does not contribute to log probability.)
        expected_logp = logpdf(Bernoulli(0.3), 1) + logpdf(Normal(2, 1), 2.5)

        @test haskey(env, :I)
        @test haskey(env, :X)
        @test haskey(env, :Y)
        @test env[:I] == 1
        @test env[:X] == 2.5
        @test env[:Y] == 3.5
        @test logp ≈ expected_logp atol = 1e-4

        println("Mixture Network with Deterministic Node Log probability: ", logp)
    end

    @testset "Conditional Network Test" begin
        # Create a new Bayesian network.
        bn = BayesianNetwork{Symbol}()

        # Add the first stochastic node: Y1 ~ Normal(0, 1)
        # Wrap in a zero-argument function so it is callable.
        println("DEBUG: Adding Y1 => Normal(0, 1)")
        add_stochastic_vertex!(bn, :Y1, () -> Normal(0, 1), false, :continuous)

        # Add the second stochastic node: Y2 ~ Normal(Y1, 1)
        # Its distribution depends on Y1.
        println("DEBUG: Adding Y2 => Normal(Y1, 1)")
        add_stochastic_vertex!(bn, :Y2, (y1) -> Normal(y1, 1), false, :continuous)

        # Add the dependency edge: Y1 is a parent of Y2.
        println("DEBUG: Adding edge Y1 => Y2")
        add_edge!(bn, :Y1, :Y2)

        # Set specific values for Y1 and Y2.
        # Here we choose: Y1 = 0.2 and Y2 = 0.5.
        new_values = deepcopy(bn.values)
        new_values = BangBang.setindex!!(new_values, 0.2, :Y1)
        new_values = BangBang.setindex!!(new_values, 0.5, :Y2)

        # Create a new Bayesian network instance with the updated values.
        bn = BayesianNetwork(
            bn.graph,
            bn.names,
            bn.names_to_ids,
            new_values,
            bn.distributions,
            bn.deterministic_functions,
            bn.stochastic_ids,
            bn.deterministic_ids,
            bn.is_stochastic,
            bn.is_observed,
            bn.node_types,
        )

        # Evaluate the network.
        env, logp = evaluate(bn)

        # Expected log probability:
        # For Y1: logpdf(Normal(0,1), 0.2)
        # For Y2: since Y1 = 0.2, Y2 ~ Normal(0.2,1) => logpdf(Normal(0.2,1), 0.5)
        expected_logp = logpdf(Normal(0, 1), 0.2) + logpdf(Normal(0.2, 1), 0.5)

        @test haskey(env, :Y1)
        @test haskey(env, :Y2)
        @test env[:Y1] == 0.2
        @test env[:Y2] == 0.5
        @test logp ≈ expected_logp atol = 1e-4
    end
end
