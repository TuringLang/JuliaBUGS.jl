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
	evaluate_with_marginalization,
	_marginalize_recursive,
	evaluate_with_marginalization_legacy,
	_marginalize_recursive_legacy,
	_precompute_minimal_cache_keys,
    moralize,
    evaluate_with_marginalization_ordered,
    topological_sort_with_heuristic
using BangBang
using JuliaBUGS
using JuliaBUGS: @bugs, compile, NodeInfo, VarName
using Bijectors: Bijectors
using AbstractPPL

using Printf
using TimerOutputs
using BenchmarkTools

function marginalize_without_memo(bn, params)
	sorted_node_ids = topological_sort_by_dfs(bn.graph)
	env = deepcopy(bn.evaluation_env)

	# Use the original function without memo
	logp = JuliaBUGS.ProbabilisticGraphicalModels._marginalize_recursive_legacy(
		bn, env, sorted_node_ids, params, 1, bn.transformed_var_lengths,
	)
	return env, logp
end

function marginalize_with_memo(bn, params)
	sorted_node_ids = topological_sort_by_dfs(bn.graph)
	env = deepcopy(bn.evaluation_env)
	memo = Dict{Tuple{Int, Int, UInt64}, Any}() # there is a difference between pass this and not passing this
	minimal_keys = JuliaBUGS.ProbabilisticGraphicalModels._precompute_minimal_cache_keys(bn)

	# Use the enhanced function with memo
	logp = JuliaBUGS.ProbabilisticGraphicalModels._marginalize_recursive(
		bn, env, sorted_node_ids, params, 1, bn.transformed_var_lengths, memo, :minimal_key, minimal_keys,
	)
	return env, logp, length(memo)
end

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
			bn, [:A, :NonExistent], [:F], [:B],
		)
		@test_throws KeyError is_conditionally_independent(
			bn, [:A], [:F, :NonExistent], [:B],
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

		inits = (a = 1.0, b = 2.0, c = 3.0)

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

		complex_inits = (a = 1.0, b = 2.0, c = 3.0)

		complex_compiled_model = compile(complex_model, NamedTuple(), complex_inits)

		complex_g = complex_compiled_model.g

		# Translate the complex BUGSGraph to a BayesianNetwork
		complex_bn = translate_BUGSGraph_to_BayesianNetwork(
			complex_g, complex_compiled_model.evaluation_env,
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

		inits = (a = 1.0, b = 2.0, c = 3.0)

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

		complex_inits = (a = 1.0, b = 2.0, c = 3.0)

		complex_compiled_model = compile(complex_model, NamedTuple(), complex_inits)

		complex_g = complex_compiled_model.g

		# Translate the complex BUGSGraph to a BayesianNetwork
		complex_bn = translate_BUGSGraph_to_BayesianNetwork(
			complex_g, complex_compiled_model.evaluation_env,
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
			loop_g, loop_compiled_model.evaluation_env,
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
				loop_compiled_model.g, loop_compiled_model.evaluation_env,
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
				model, params; temperature = 1.0,
			)

			# Our implementation
			bn_env, bn_logjoint = evaluate_with_values(bn, params)

			# Manual calculation that matches BUGSModel
			# First parameter is sigma
			sigma_param = params[1]
			b_sigma = Bijectors.bijector(Gamma(2, 3))
			b_sigma_inv = Bijectors.inverse(b_sigma)
			sigma_reconstructed = JuliaBUGS.reconstruct(
				b_sigma_inv, Gamma(2, 3), [sigma_param],
			)
			sigma_val, sigma_logjac = Bijectors.with_logabsdet_jacobian(
				b_sigma_inv, sigma_reconstructed,
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
				bugs_model.g, bugs_model.evaluation_env,
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
				bugs_model.g, bugs_model.evaluation_env,
			)

			# Create random parameters
			params = rand(3)

			# Evaluate BUGSModel with parameters
			bugs_env, (bugs_logprior, bugs_loglikelihood, bugs_logjoint) = JuliaBUGS._tempered_evaluate!!(
				bugs_model, params; temperature = 1.0,
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
				bugs_model.g, bugs_model.evaluation_env,
			)

			# Create random parameters
			params = rand(4)

			# Evaluate BUGSModel with parameters
			bugs_env, (bugs_logprior, bugs_loglikelihood, bugs_logjoint) = JuliaBUGS._tempered_evaluate!!(
				bugs_model, params; temperature = 1.0,
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
		function set_node_types(bn::BayesianNetwork{V, T, F}, var_types) where {V, T, F}
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
		function set_observations(bn::BayesianNetwork{V, T, F}, observations) where {V, T, F}
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
			result = Dict{String, Any}()
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
			bn, discrete_vars, observations, expected_logp; params = Float64[], rtol = 1e-6,
		)
			# Set node types for discrete variables
			bn = set_node_types(bn, discrete_vars)

			# Set observations
			bn = set_observations(bn, observations)

			# Run marginalization
			_, margin_logp = evaluate_with_marginalization(bn, params, caching_strategy = :minimal_key)

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
					compiled_model.g, compiled_model.evaluation_env,
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
					compiled_model.g, compiled_model.evaluation_env,
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
					compiled_model.g, compiled_model.evaluation_env, compiled_model,
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
					params = [x_param],
				)
			end

			@testset "4-state HMM with manual verification" begin
				# Create a 4-state HMM with transition dependencies
				model_def = @bugs begin
					# Initial state probability
					p_init_1 = 0.6

					# States (z1 through z4)
					z1 ~ Bernoulli(p_init_1)

					# Transition probabilities
					p_1to1 = 0.7  # Probability of staying in state 1
					p_0to1 = 0.3  # Probability of moving from state 0 to 1

					# State transitions with dependencies
					# z2 depends on z1
					p_z2 = p_0to1 * (1 - z1) + p_1to1 * z1
					z2 ~ Bernoulli(p_z2)

					# z3 depends on z2
					p_z3 = p_0to1 * (1 - z2) + p_1to1 * z2
					z3 ~ Bernoulli(p_z3)

					# z4 depends on z3
					p_z4 = p_0to1 * (1 - z3) + p_1to1 * z3
					z4 ~ Bernoulli(p_z4)

					# Emission parameters
					mu_0 = 0.0
					mu_1 = 5.0
					sigma_0 = 1.0
					sigma_1 = 2.0

					# Emissions based on states
					mu_y1 = mu_0 * (1 - z1) + mu_1 * z1
					sigma_y1 = sigma_0 * (1 - z1) + sigma_1 * z1
					y1 ~ Normal(mu_y1, sigma_y1)

					mu_y2 = mu_0 * (1 - z2) + mu_1 * z2
					sigma_y2 = sigma_0 * (1 - z2) + sigma_1 * z2
					y2 ~ Normal(mu_y2, sigma_y2)

					mu_y3 = mu_0 * (1 - z3) + mu_1 * z3
					sigma_y3 = sigma_0 * (1 - z3) + sigma_1 * z3
					y3 ~ Normal(mu_y3, sigma_y3)

					mu_y4 = mu_0 * (1 - z4) + mu_1 * z4
					sigma_y4 = sigma_0 * (1 - z4) + sigma_1 * z4
					y4 ~ Normal(mu_y4, sigma_y4)
				end

				# Compile the model
				compiled_model = compile(model_def, NamedTuple())

				# Convert to BayesianNetwork
				bn = translate_BUGSGraph_to_BayesianNetwork(
					compiled_model.g, compiled_model.evaluation_env,
				)

				# Find z variables and mark them as discrete
				var_types = Dict()
				z_vars = []
				y_vars = []

				for var in bn.names
					var_str = string(var)
					if startswith(var_str, "z") && length(var_str) == 2
						var_types[var] = :discrete
						push!(z_vars, var)
					elseif startswith(var_str, "y") && length(var_str) == 2
						push!(y_vars, var)
					end
				end

				# Sort variables to ensure consistent ordering
				sort!(z_vars; by = x -> parse(Int, string(x)[2:end]))
				sort!(y_vars; by = x -> parse(Int, string(x)[2:end]))

				# Set node types
				bn = set_node_types(bn, var_types)

				# Set observed values for y
				y_values = [1.5, 4.2, 0.8, 3.1]
				observations = Dict(y_vars[i] => y_values[i] for i in 1:4)
				bn = set_observations(bn, observations)

				# Parameters for continuous variables
				params = Float64[]

				# Call our recursive implementation
				_, margin_logp = evaluate_with_marginalization(
					bn, params, caching_strategy = :minimal_key,
				)

				# Manual calculation
				# Model parameters
				p_init_1 = 0.6
				p_1to1 = 0.7
				p_0to1 = 0.3

				mu_0 = 0.0
				mu_1 = 5.0
				sigma_0 = 1.0
				sigma_1 = 2.0

				# Function to calculate transition probability P(z_next|z_prev)
				function trans_prob(prev_state, next_state)
					if prev_state == 0
						return next_state == 0 ? 1.0 - p_0to1 : p_0to1
					else # prev_state == 1
						return next_state == 0 ? 1.0 - p_1to1 : p_1to1
					end
				end

				# Function to calculate emission probability P(y|z)
				function emission_prob(y, z)
					mu = z == 0 ? mu_0 : mu_1
					sigma = z == 0 ? sigma_0 : sigma_1
					return pdf(Normal(mu, sigma), y)
				end

				# Calculate probability for a specific state sequence
				function sequence_prob(states)
					# Initial state probability
					p = states[1] == 0 ? 1.0 - p_init_1 : p_init_1

					# Transition probabilities
					for i in 2:length(states)
						p *= trans_prob(states[i-1], states[i])
					end

					# Emission probabilities
					for i in 1:length(states)
						p *= emission_prob(y_values[i], states[i])
					end

					return p
				end

				# Calculate marginal by summing over all possible state sequences
				total_prob = 0.0

				# Generate and evaluate all 16 possible sequences
				for s1 in [0, 1]
					for s2 in [0, 1]
						for s3 in [0, 1]
							for s4 in [0, 1]
								states = [s1, s2, s3, s4]
								seq_p = sequence_prob(states)
								total_prob += seq_p
							end
						end
					end
				end

				manual_logp = log(total_prob)
				@test isapprox(margin_logp, manual_logp, rtol = 1E-6)
			end
		end

		@testset "A→C, A→B→D structure with marginalization" begin
			# Create a model with the specified structure:
			# A (Bernoulli) → C (Observed)
			# ↓
			# B (Bernoulli) → D (Observed)
			model_def = @bugs begin
				# A: First discrete variable (Bernoulli)
				a ~ Bernoulli(0.4)  # Prior probability P(A=1) = 0.4

				# B: Second discrete variable, depends on A
				# P(B=1|A=0) = 0.2, P(B=1|A=1) = 0.8
				p_b_given_a0 = 0.2
				p_b_given_a1 = 0.8
				p_b = p_b_given_a0 * (1 - a) + p_b_given_a1 * a
				b ~ Bernoulli(p_b)

				# C: Observed variable that depends on A
				# Different normal distributions based on A's state
				mu_c_a0 = 0.0
				mu_c_a1 = 3.0
				sigma_c = 1.0
				mu_c = mu_c_a0 * (1 - a) + mu_c_a1 * a
				c ~ Normal(mu_c, sigma_c)

				# D: Observed variable that depends on B
				# Different normal distributions based on B's state
				mu_d_b0 = -1.0
				mu_d_b1 = 2.0
				sigma_d = 0.8
				mu_d = mu_d_b0 * (1 - b) + mu_d_b1 * b
				d ~ Normal(mu_d, sigma_d)
			end

			# Compile the model
			compiled_model = compile(model_def, NamedTuple())

			# Convert to BayesianNetwork
			bn = translate_BUGSGraph_to_BayesianNetwork(
				compiled_model.g, compiled_model.evaluation_env,
			)

			# Get variables
			vars = Dict()
			for var in bn.names
				var_str = string(var)
				vars[var_str] = var
			end

			# Set A and B as discrete variables
			discrete_vars = Dict(vars["a"] => :discrete, vars["b"] => :discrete)

			# Set observed values for C and D
			c_value = 2.5
			d_value = 1.8
			observations = Dict(vars["c"] => c_value, vars["d"] => d_value)

			# Manually calculate expected marginal likelihood
			function calculate_marginal_likelihood()
				# Model parameters
				p_a1 = 0.4  # P(A=1)
				p_a0 = 0.6  # P(A=0)

				p_b1_given_a0 = 0.2  # P(B=1|A=0)
				p_b0_given_a0 = 0.8  # P(B=0|A=0)
				p_b1_given_a1 = 0.8  # P(B=1|A=1)
				p_b0_given_a1 = 0.2  # P(B=0|A=1)

				mu_c_a0 = 0.0
				mu_c_a1 = 3.0
				sigma_c = 1.0

				mu_d_b0 = -1.0
				mu_d_b1 = 2.0
				sigma_d = 0.8

				# Calculate likelihoods for each combination of A and B
				# P(C|A)
				p_c_given_a0 = pdf(Normal(mu_c_a0, sigma_c), c_value)
				p_c_given_a1 = pdf(Normal(mu_c_a1, sigma_c), c_value)

				# P(D|B)
				p_d_given_b0 = pdf(Normal(mu_d_b0, sigma_d), d_value)
				p_d_given_b1 = pdf(Normal(mu_d_b1, sigma_d), d_value)

				# Calculate joint probabilities for all four combinations
				# P(A=0,B=0,C,D) = P(A=0) * P(B=0|A=0) * P(C|A=0) * P(D|B=0)
				p_a0_b0 = p_a0 * p_b0_given_a0 * p_c_given_a0 * p_d_given_b0

				# P(A=0,B=1,C,D) = P(A=0) * P(B=1|A=0) * P(C|A=0) * P(D|B=1)
				p_a0_b1 = p_a0 * p_b1_given_a0 * p_c_given_a0 * p_d_given_b1

				# P(A=1,B=0,C,D) = P(A=1) * P(B=0|A=1) * P(C|A=1) * P(D|B=0)
				p_a1_b0 = p_a1 * p_b0_given_a1 * p_c_given_a1 * p_d_given_b0

				# P(A=1,B=1,C,D) = P(A=1) * P(B=1|A=1) * P(C|A=1) * P(D|B=1)
				p_a1_b1 = p_a1 * p_b1_given_a1 * p_c_given_a1 * p_d_given_b1

				# Marginal likelihood = sum of all combinations
				marginal = p_a0_b0 + p_a0_b1 + p_a1_b0 + p_a1_b1

				# Return log probability
				return log(marginal)
			end

			# Calculate expected result
			expected_logp = calculate_marginal_likelihood()

			# Set node types
			bn = set_node_types(bn, discrete_vars)

			# Set observations
			bn = set_observations(bn, observations)

			# Run marginalization
			params = Float64[]  # No continuous parameters in this example
			_, margin_logp = evaluate_with_marginalization(bn, params, caching_strategy = :minimal_key)

			# Calculate expected probability for each state combination
			p_a0 = 0.6
			p_a1 = 0.4
			p_b0_given_a0 = 0.8
			p_b1_given_a0 = 0.2
			p_b0_given_a1 = 0.2
			p_b1_given_a1 = 0.8

			p_c_given_a0 = pdf(Normal(0.0, 1.0), c_value)
			p_c_given_a1 = pdf(Normal(3.0, 1.0), c_value)
			p_d_given_b0 = pdf(Normal(-1.0, 0.8), d_value)
			p_d_given_b1 = pdf(Normal(2.0, 0.8), d_value)

			p_a0_b0 = p_a0 * p_b0_given_a0 * p_c_given_a0 * p_d_given_b0
			p_a0_b1 = p_a0 * p_b1_given_a0 * p_c_given_a0 * p_d_given_b1
			p_a1_b0 = p_a1 * p_b0_given_a1 * p_c_given_a1 * p_d_given_b0
			p_a1_b1 = p_a1 * p_b1_given_a1 * p_c_given_a1 * p_d_given_b1

			total_manual = p_a0_b0 + p_a0_b1 + p_a1_b0 + p_a1_b1
			log_manual = log(total_manual)

			@test isapprox(margin_logp, expected_logp, rtol = 1E-6)
		end
	end
	@testset "Dynamic Programming in Marginalization" begin

		# Helper function to create graph without using compiler
		function create_chain_bayesian_network(n_chain)
			# Create initial network
			bn = BayesianNetwork{VarName}()

			# Initialize loop_vars to track as we build
			loop_vars = Dict{VarName, NamedTuple}()

			# Track variables to create full environment later
			all_vars = Dict{Symbol, Any}()

			# Add first node
			first_var = VarName(Symbol("z[1]"))
			add_stochastic_vertex!(
				bn, first_var, (_, _) -> Bernoulli(0.5), false, :discrete,
			)
			loop_vars[first_var] = (;)  # Empty named tuple
			all_vars[Symbol("z[1]")] = 0  # Initialize with value 0

			# Add subsequent nodes with dependencies
			for i in 2:n_chain
				var = VarName(Symbol("z[$i]"))
				prev_var = VarName(Symbol("z[$(i-1)]"))

				# Add node
				add_stochastic_vertex!(
					bn,
					var,
					(env, _) -> begin
						prev_val = AbstractPPL.get(env, prev_var)
						p_stay = 0.7
						p_switch = 0.3
						p = p_switch * (1 - prev_val) + p_stay * prev_val
						return Bernoulli(p)
					end,
					false,
					:discrete,
				)
				loop_vars[var] = (;)  # Empty named tuple
				all_vars[Symbol("z[$i]")] = 0  # Initialize with value 0

				# Add dependency edge
				add_edge!(bn, prev_var, var)
			end

			# Add observable at the end
			y_var = VarName(:y)
			last_var = VarName(Symbol("z[$n_chain]"))

			add_stochastic_vertex!(
				bn,
				y_var,
				(env, _) -> begin
					z_val = AbstractPPL.get(env, last_var)
					mu = z_val * 5.0
					return Normal(mu, 1.0)
				end,
				true,
				:continuous,
			)
			loop_vars[y_var] = (;)  # Empty named tuple

			# Add dependency edge
			add_edge!(bn, last_var, y_var)

			# Set observation value for y
			all_vars[:y] = 4.2

			# Create the evaluation environment
			eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

			# Create new bn with full evaluation environment
			new_bn = BayesianNetwork(
				bn.graph,
				bn.names,
				bn.names_to_ids,
				eval_env,  # Full environment with all variables
				loop_vars,
				bn.distributions,
				bn.deterministic_functions,
				bn.stochastic_ids,
				bn.deterministic_ids,
				bn.is_stochastic,
				bn.is_observed,
				bn.node_types,
				Dict{VarName, Int}(),  # empty transformed_var_lengths
				0,  # zero transformed_param_length
			)

			return new_bn
		end
		@testset "Performance with Deep Discrete Graph" begin
			# Create a chain of discrete variables manually to avoid compilation issues
			n_chain = 5
			bn = create_chain_bayesian_network(n_chain)

			# No continuous parameters in this example
			params = Float64[]

			# Measure performance
			t1 = @elapsed _, logp1 = marginalize_without_memo(bn, params)
			t2 = @elapsed _, logp2, memo_size = marginalize_with_memo(bn, params)

			# Verify results match
			@test isapprox(logp1, logp2, rtol = 1e-10)

			# Print performance metrics
			@info "Marginalization Performance" without_memo = t1 with_memo = t2 speedup =
				t1 / t2 memo_size = memo_size

			# Make sure there was at least some memoization
			@test memo_size > 0

			# For a chain of length 5, we could have at most 2*2^n_chain states
			# The factor of 2 accounts for the fact that each node can be visited 
			# once per possible configuration of its ancestors
			@test memo_size <= 2 * 2^n_chain

			# Performance should be better with memoization
			# This was previously marked as broken, but it's working now
			@test t2 < t1
		end

		@testset "Correctness with Tricky Dependency Graph" begin
			# Create a complex graph manually to ensure it's acyclic
			# Start with an initial network
			original_bn = BayesianNetwork{VarName}()

			# Initialize loop_vars to track as we build
			loop_vars = Dict{VarName, NamedTuple}()

			# Track all variables to create full environment
			all_vars = Dict{Symbol, Any}()

			# Root nodes
			x_var = VarName(:x)
			y_var = VarName(:y)

			# Add them to the network
			add_stochastic_vertex!(
				original_bn, x_var, (_, _) -> Bernoulli(0.3), false, :discrete,
			)
			add_stochastic_vertex!(
				original_bn, y_var, (_, _) -> Bernoulli(0.7), false, :discrete,
			)
			loop_vars[x_var] = (;)
			loop_vars[y_var] = (;)
			all_vars[:x] = 0  # Initialize with value 0
			all_vars[:y] = 0  # Initialize with value 0

			# Variable with multiple parents
			z_var = VarName(:z)
			add_stochastic_vertex!(
				original_bn,
				z_var,
				(env, _) -> begin
					x_val = AbstractPPL.get(env, x_var)
					y_val = AbstractPPL.get(env, y_var)
					p = 0.1 + 0.3 * x_val + 0.4 * y_val + 0.2 * x_val * y_val
					return Bernoulli(p)
				end,
				false,
				:discrete,
			)
			loop_vars[z_var] = (;)
			all_vars[:z] = 0  # Initialize with value 0

			# Add dependency edges
			add_edge!(original_bn, x_var, z_var)
			add_edge!(original_bn, y_var, z_var)

			# Another dependent variable
			w_var = VarName(:w)
			add_stochastic_vertex!(
				original_bn,
				w_var,
				(env, _) -> begin
					z_val = AbstractPPL.get(env, z_var)
					p = 0.2 + 0.6 * z_val
					return Bernoulli(p)
				end,
				false,
				:discrete,
			)
			loop_vars[w_var] = (;)
			all_vars[:w] = 0  # Initialize with value 0

			# Add dependency edge
			add_edge!(original_bn, z_var, w_var)

			# Observed variables
			obs1_var = VarName(:obs1)
			add_stochastic_vertex!(
				original_bn,
				obs1_var,
				(env, _) -> begin
					x_val = AbstractPPL.get(env, x_var)
					y_val = AbstractPPL.get(env, y_var)
					mu = x_val * 2 + y_val * 3
					return Normal(mu, 1.0)
				end,
				true,
				:continuous,
			)
			loop_vars[obs1_var] = (;)

			obs2_var = VarName(:obs2)
			add_stochastic_vertex!(
				original_bn,
				obs2_var,
				(env, _) -> begin
					z_val = AbstractPPL.get(env, z_var)
					w_val = AbstractPPL.get(env, w_var)
					mu = z_val * 4 + w_val * 5
					return Normal(mu, 1.0)
				end,
				true,
				:continuous,
			)
			loop_vars[obs2_var] = (;)

			# Add dependency edges
			add_edge!(original_bn, x_var, obs1_var)
			add_edge!(original_bn, y_var, obs1_var)
			add_edge!(original_bn, z_var, obs2_var)
			add_edge!(original_bn, w_var, obs2_var)

			# Set observations
			obs1_val = 2.5
			obs2_val = 3.7
			all_vars[:obs1] = obs1_val
			all_vars[:obs2] = obs2_val

			# Create the evaluation environment
			eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

			# Create a new BayesianNetwork with all variables in the environment
			bn = BayesianNetwork(
				original_bn.graph,
				original_bn.names,
				original_bn.names_to_ids,
				eval_env,
				loop_vars,
				original_bn.distributions,
				original_bn.deterministic_functions,
				original_bn.stochastic_ids,
				original_bn.deterministic_ids,
				original_bn.is_stochastic,
				original_bn.is_observed,
				original_bn.node_types,
				Dict{VarName, Int}(),
				0,
			)

			# Run with original function
			env1, logp1 = marginalize_without_memo(bn, Float64[])

			# Run with memoized function
			env2, logp2, memo_size = marginalize_with_memo(bn, Float64[])

			# Verify results match
			@test isapprox(logp1, logp2, rtol = 1e-10)

			# Should have memoized results
			@test memo_size > 0

			# For a network with 4 binary variables, the theoretical worst case
			# would be 4*2^4 = 64 states (if every node needs to be evaluated separately for
			# every possible configuration of all variables). 
			# Our memo design creates a new entry for each unique combination of node, parameter index, and environment hash
			# So we expect the memo size to be below this upper bound but potentially more than 2^4
			@test memo_size < 4 * 2^4

			# The memo size will be larger than just 2^4=16 because our implementation
			# creates unique entries for each node and environment combination
			@info "Complex graph memo statistics" memo_size = memo_size theoretical_max =
				4 * 2^4

			# Verify against a manual calculation of one specific path
			# This ensures our DP approach handles complex dependencies correctly
			function manual_calculate_specific_path(obs_values)
				# Calculate probability for x=1, y=0, z=1, w=1
				# P(x=1) = 0.3
				p_x1 = 0.3

				# P(y=0) = 0.3
				p_y0 = 0.3

				# P(z=1|x=1,y=0) = 0.1 + 0.3*1 + 0.4*0 + 0.2*1*0 = 0.4
				p_z1_given_x1_y0 = 0.4

				# P(w=1|z=1) = 0.2 + 0.6*1 = 0.8
				p_w1_given_z1 = 0.8

				# P(obs1|x=1,y=0) = Normal(1*2 + 0*3, 1.0) at obs_values[1]
				p_obs1 = pdf(Normal(2.0, 1.0), obs_values[1])

				# P(obs2|z=1,w=1) = Normal(1*4 + 1*5, 1.0) at obs_values[2]
				p_obs2 = pdf(Normal(9.0, 1.0), obs_values[2])

				# Joint probability of this specific path
				joint_prob =
					p_x1 * p_y0 * p_z1_given_x1_y0 * p_w1_given_z1 * p_obs1 * p_obs2

				return log(joint_prob)
			end

			# Extract observation values
			obs_values = [obs1_val, obs2_val]

			# Calculate log probability for a specific path
			path_logp = manual_calculate_specific_path(obs_values)

			# The full marginalized probability should be greater than this single path
			@test logp2 > path_logp
		end
	end

	@testset "Dynamic Programming Performance Analysis" begin
		# Helper function to create evaluation environment and loop_vars
		function init_network_variables(variables, init_values = nothing)
			all_vars = Dict{Symbol, Any}()
			loop_vars = Dict{VarName, NamedTuple}()

			for (i, var) in enumerate(variables)
				var_name = typeof(var) == Symbol ? var : Symbol(var)
				var_value = init_values === nothing ? 0 : init_values[i]
				all_vars[var_name] = var_value
				loop_vars[VarName(var_name)] = (;)
			end

			return all_vars, loop_vars
		end

		# Helper function to create a complete environment from variables and observations
		function create_env(variables, observations)
			merged = merge(variables, observations)
			return NamedTuple{Tuple(keys(merged))}(values(merged))
		end

		# Helper function to create a chain network of specified length
		function create_chain_network(length::Int)
			# Create initial network
			bn = BayesianNetwork{VarName}()

			# Define variables
			variables = [Symbol("z$i") for i in 1:length]
			push!(variables, :y)  # Observation variable

			# Initialize tracking
			all_vars, loop_vars = init_network_variables(variables)
			all_vars[:y] = 4.2  # Set observation

			# Add first node
			first_var = VarName(Symbol("z1"))
			add_stochastic_vertex!(
				bn, first_var, (_, _) -> Bernoulli(0.5), false, :discrete,
			)

			# Add subsequent nodes with dependencies
			for i in 2:length
				var = VarName(Symbol("z$i"))
				prev_var = VarName(Symbol("z$(i-1)"))

				# Add node with dependency on previous node
				add_stochastic_vertex!(
					bn,
					var,
					(env, _) -> begin
						prev_val = AbstractPPL.get(env, prev_var)
						p_stay = 0.7
						p_switch = 0.3
						p = p_switch * (1 - prev_val) + p_stay * prev_val
						return Bernoulli(p)
					end,
					false,
					:discrete,
				)

				# Add dependency edge
				add_edge!(bn, prev_var, var)
			end

			# Add observable at the end
			y_var = VarName(:y)
			last_var = VarName(Symbol("z$length"))

			add_stochastic_vertex!(
				bn,
				y_var,
				(env, _) -> begin
					z_val = AbstractPPL.get(env, last_var)
					mu = z_val * 5.0
					return Normal(mu, 1.0)
				end,
				true,
				:continuous,
			)

			# Add dependency edge
			add_edge!(bn, last_var, y_var)

			# Create evaluation environment
			eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

			# Create final network
			new_bn = BayesianNetwork(
				bn.graph,
				bn.names,
				bn.names_to_ids,
				eval_env,
				loop_vars,
				bn.distributions,
				bn.deterministic_functions,
				bn.stochastic_ids,
				bn.deterministic_ids,
				bn.is_stochastic,
				bn.is_observed,
				bn.node_types,
				Dict{VarName, Int}(),
				0,
			)

			return new_bn
		end

		# Helper function to create a tree network of specified depth
		function create_tree_network(depth::Int)
			# Create initial network
			bn = BayesianNetwork{VarName}()

			# Define variables - a binary tree has 2^depth-1 nodes
			node_count = 2^depth - 1
			variables = [Symbol("z$i") for i in 1:node_count]
			push!(variables, :y)  # Observation variable

			# Initialize tracking
			all_vars, loop_vars = init_network_variables(variables)
			all_vars[:y] = 3.7  # Set observation

			# Add root node
			root_var = VarName(Symbol("z1"))
			add_stochastic_vertex!(bn, root_var, (_, _) -> Bernoulli(0.5), false, :discrete)

			# Add nodes level by level
			for level in 1:(depth-1)
				start_idx = 2^level
				end_idx = 2^(level + 1) - 1
				parent_start = 2^(level - 1)

				for i in start_idx:end_idx
					var = VarName(Symbol("z$i"))
					parent_idx = parent_start + div(i - start_idx, 2)
					parent_var = VarName(Symbol("z$parent_idx"))

					# Add node with dependency on parent
					add_stochastic_vertex!(
						bn,
						var,
						(env, _) -> begin
							parent_val = AbstractPPL.get(env, parent_var)
							p_base = 0.3 + 0.4 * parent_val  # Value dependent on parent
							return Bernoulli(p_base)
						end,
						false,
						:discrete,
					)

					# Add dependency edge
					add_edge!(bn, parent_var, var)
				end
			end

			# Add observable that depends on leaf nodes
			y_var = VarName(:y)
			leaf_start = 2^(depth - 1)
			leaf_end = 2^depth - 1

			add_stochastic_vertex!(
				bn,
				y_var,
				(env, _) -> begin
					# Observable depends on average of leaf values
					leaf_sum = 0.0
					for i in leaf_start:leaf_end
						leaf_var = VarName(Symbol("z$i"))
						leaf_sum += AbstractPPL.get(env, leaf_var)
					end
					leaf_avg = leaf_sum / (leaf_end - leaf_start + 1)
					mu = leaf_avg * 10.0
					return Normal(mu, 1.0)
				end,
				true,
				:continuous,
			)

			# Add dependency edges from all leaf nodes
			for i in leaf_start:leaf_end
				leaf_var = VarName(Symbol("z$i"))
				add_edge!(bn, leaf_var, y_var)
			end

			# Create evaluation environment
			eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

			# Create final network
			new_bn = BayesianNetwork(
				bn.graph,
				bn.names,
				bn.names_to_ids,
				eval_env,
				loop_vars,
				bn.distributions,
				bn.deterministic_functions,
				bn.stochastic_ids,
				bn.deterministic_ids,
				bn.is_stochastic,
				bn.is_observed,
				bn.node_types,
				Dict{VarName, Int}(),
				0,
			)

			return new_bn
		end

		# Helper function to create a grid network (each node depends on nodes above and to the left)
		function create_grid_network(width::Int, height::Int)
			# Create initial network
			bn = BayesianNetwork{VarName}()

			# Define variables
			variables = [Symbol("z$(i)_$(j)") for i in 1:height for j in 1:width]
			push!(variables, :y)  # Observation variable

			# Initialize tracking
			all_vars, loop_vars = init_network_variables(variables)
			all_vars[:y] = 2.8  # Set observation

			# Add nodes row by row, column by column
			for i in 1:height
				for j in 1:width
					var = VarName(Symbol("z$(i)_$(j)"))

					# Determine dependencies
					has_left = j > 1
					has_above = i > 1

					# Add node with appropriate dependencies
					if !has_left && !has_above
						# Top-left node has no dependencies
						add_stochastic_vertex!(
							bn, var, (_, _) -> Bernoulli(0.5), false, :discrete,
						)
					else
						# Node depends on nodes above and/or to the left
						add_stochastic_vertex!(
							bn,
							var,
							(env, _) -> begin
								p_base = 0.3  # Base probability

								if has_left
									left_var = VarName(Symbol("z$(i)_$(j-1)"))
									left_val = AbstractPPL.get(env, left_var)
									p_base += 0.2 * left_val
								end

								if has_above
									above_var = VarName(Symbol("z$(i-1)_$(j)"))
									above_val = AbstractPPL.get(env, above_var)
									p_base += 0.3 * above_val
								end

								return Bernoulli(min(p_base, 0.95))  # Cap probability
							end,
							false,
							:discrete,
						)

						# Add dependency edges
						if has_left
							left_var = VarName(Symbol("z$(i)_$(j-1)"))
							add_edge!(bn, left_var, var)
						end

						if has_above
							above_var = VarName(Symbol("z$(i-1)_$(j)"))
							add_edge!(bn, above_var, var)
						end
					end
				end
			end

			# Add observable that depends on bottom-right nodes
			y_var = VarName(:y)

			add_stochastic_vertex!(
				bn,
				y_var,
				(env, _) -> begin
					# Observable depends on the value of the bottom-right node
					bottom_right_var = VarName(Symbol("z$(height)_$(width)"))
					bottom_right_val = AbstractPPL.get(env, bottom_right_var)
					mu = bottom_right_val * 5.0
					return Normal(mu, 1.0)
				end,
				true,
				:continuous,
			)

			# Add dependency edge from bottom-right node
			bottom_right_var = VarName(Symbol("z$(height)_$(width)"))
			add_edge!(bn, bottom_right_var, y_var)

			# Create evaluation environment
			eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

			# Create final network
			new_bn = BayesianNetwork(
				bn.graph,
				bn.names,
				bn.names_to_ids,
				eval_env,
				loop_vars,
				bn.distributions,
				bn.deterministic_functions,
				bn.stochastic_ids,
				bn.deterministic_ids,
				bn.is_stochastic,
				bn.is_observed,
				bn.node_types,
				Dict{VarName, Int}(),
				0,
			)

			return new_bn
		end

		@testset "Chain Network Scaling - Updated Test" begin
			# Let's modify the test to accurately check for the improved pattern

			# Test chain network performance for increasing lengths
			# chain_lengths = [3, 5, 7, 9,11,13,15,17,19]
			# chain_lengths = [4, 6, 8, 10, 12, 14, 16, 18, 20]  # Adjusted for better scaling
			chain_lengths = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]  # For initial testing
			# Track performance metrics
			standard_times = Float64[]
			dp_times = Float64[]
			memo_sizes = Int[]
			speedups = Float64[]
			state_counts = Int[]

			# Run the tests and collect data
			for length in chain_lengths
				bn = create_chain_network(length)
				params = Float64[]
				state_count = 2^length
				push!(state_counts, state_count)

				# ====== Standard Method (Without Memoization) ======
				# Warmup run (JIT compilation)
				_, _ = marginalize_without_memo(bn, params)
				# Timed run (steady-state)
				standard_time = @elapsed _, _ = marginalize_without_memo(bn, params)
				push!(standard_times, standard_time)

				# ====== DP Method (With Memoization) ======
				# Warmup run (JIT + memoization cache population)
				_, _, _ = marginalize_with_memo(bn, params)
				# Timed run (steady-state)
				dp_time = @elapsed _, _, memo_size = marginalize_with_memo(bn, params)
				push!(dp_times, dp_time)
				push!(memo_sizes, memo_size)

				# Calculate speedup
				speedup = standard_time / dp_time
				push!(speedups, speedup)

				# Print results
				@info "Chain length $length" standard_time dp_time speedup memo_size state_count

				# Verify correctness (results should match)
				_, logp1 = marginalize_without_memo(bn, params)
				_, logp2, _ = marginalize_with_memo(bn, params)
				@test isapprox(logp1, logp2, rtol = 1e-10)
			end

			# Summarize results
			@info "Chain Network Performance Summary" chain_lengths standard_times dp_times speedups memo_sizes state_counts

			# Check for the improved pattern in memo sizes
			for i in 1:length(chain_lengths)
				# The actual pattern is 2n + 1 where n is the chain length
				expected_memo_size = 2 * chain_lengths[i] + 1

				# Test that our memo size matches this improved pattern
				@test memo_sizes[i] == expected_memo_size

				# Also verify that this is much better than the old pattern
				old_pattern_size = 2^(chain_lengths[i] + 1) - 1
				@test memo_sizes[i] < old_pattern_size

				# Calculate the improvement factor
				improvement_factor = old_pattern_size / memo_sizes[i]
				@info "Chain length $(chain_lengths[i]) improvement" old_size =
					old_pattern_size new_size = memo_sizes[i] factor = improvement_factor
			end

			# Additional insights
			@info "Chain Speedup Analysis" chain_lengths speedups
			println(speedups)
		end


		@testset "Tree Network Scaling" begin
			# Test tree network performance for increasing depths
			tree_depths = [2, 3, 4,5]  # A depth 4 tree has 15 nodes (2^4-1)

			# Track performance metrics
			standard_times = Float64[]
			dp_times = Float64[]
			memo_sizes = Int[]
			speedups = Float64[]
			node_counts = Int[]

			for depth in tree_depths
				bn = create_tree_network(depth)
				params = Float64[]

				# Calculate node count
				node_count = 2^depth - 1
				push!(node_counts, node_count)

				# Run without memoization
				println("Running without memoization")
				println("Node count: $node_count")
				standard_time = @elapsed _, _ = marginalize_without_memo(bn, params)
				push!(standard_times, standard_time)

				# Run with memoization
				println("Running with memoization")
				println("Node count: $node_count")
				dp_time = @elapsed _, _, memo_size = marginalize_with_memo(bn, params)
				push!(dp_times, dp_time)
				push!(memo_sizes, memo_size)

				# Calculate speedup
				speedup = standard_time / dp_time
				push!(speedups, speedup)

				# Print results
				@info "Tree depth $depth (nodes: $node_count)" standard_time dp_time speedup memo_size

				# Verify correctness (results should match)
				_, logp1 = marginalize_without_memo(bn, params)
				_, logp2, _ = marginalize_with_memo(bn, params)
				@test isapprox(logp1, logp2, rtol = 1e-10)
			end

			# Summarize results
			@info "Tree Network Performance Summary" tree_depths node_counts standard_times dp_times speedups memo_sizes

			# Test that for all network sizes, the results are correct
			@test all(speedups .!= 0.0)  # Just ensure we got valid measurements

			# The memo size should grow with network complexity
			@test memo_sizes[end] > memo_sizes[1]

			# For tree networks, the memo size grows very quickly
			# Test that memo_size is at most (node_count+1) * 2^node_count
			# This checks that our memoization scheme is not wasteful
			for i in 1:length(tree_depths)
				@test memo_sizes[i] <= (node_counts[i] + 1) * 2^node_counts[i]
			end

			println(speedups)
		end

		@testset "Grid Network Scaling" begin
			# Test grid networks with different sizes
			grid_sizes = [(2, 2), (2, 3), (3, 3), (3, 4), (4, 4)]  # (width, height)

			# Track performance metrics
			standard_times = Float64[]
			dp_times = Float64[]
			memo_sizes = Int[]
			speedups = Float64[]
			node_counts = Int[]

			for (width, height) in grid_sizes
				bn = create_grid_network(width, height)
				params = Float64[]

				# Calculate node count
				node_count = width * height
				push!(node_counts, node_count)

				# Run without memoization
				standard_time = @elapsed _, _ = marginalize_without_memo(bn, params)
				push!(standard_times, standard_time)

				# Run with memoization
				dp_time = @elapsed _, _, memo_size = marginalize_with_memo(bn, params)
				push!(dp_times, dp_time)
				push!(memo_sizes, memo_size)

				# Calculate speedup
				speedup = standard_time / dp_time
				push!(speedups, speedup)

				# Print results
				@info "Grid size $(width)x$(height) (nodes: $node_count)" standard_time dp_time speedup memo_size

				# Verify correctness (results should match)
				_, logp1 = marginalize_without_memo(bn, params)
				_, logp2, _ = marginalize_with_memo(bn, params)
				@test isapprox(logp1, logp2, rtol = 1e-10)
			end

			# Summarize results
			@info "Grid Network Performance Summary" grid_sizes node_counts standard_times dp_times speedups memo_sizes

			# Test that the memo size grows with the number of nodes
			@test all(diff(memo_sizes) .> 0)

			# Test that the amount of memoization is related to the complexity
			# For grid networks, memo_size should be at most 2*2^(width*height)
			# This checks that our memoization scheme is not wasteful
			for i in 1:length(grid_sizes)
				@test memo_sizes[i] <= 2 * 2^node_counts[i]
			end
		end

		# Overall analysis for all network types
		@testset "Comparative Analysis" begin
			# Test different network types with similar numbers of nodes
			# Use networks with approximately 7-9 nodes each
			chain_bn = create_chain_network(8)        # 8 nodes
			tree_bn = create_tree_network(3)          # 7 nodes
			grid_bn = create_grid_network(3, 3)       # 9 nodes

			networks = [("Chain", chain_bn), ("Tree", tree_bn), ("Grid", grid_bn)]

			# Track performance metrics
			standard_times = Float64[]
			dp_times = Float64[]
			memo_sizes = Int[]
			speedups = Float64[]
			node_counts = Int[]

			for (name, bn) in networks
				params = Float64[]

				# Count nodes
				node_count = length(bn.names) - 1  # Subtract observation node
				push!(node_counts, node_count)

				# Run without memoization
				standard_time = @elapsed _, _ = marginalize_without_memo(bn, params)
				push!(standard_times, standard_time)

				# Run with memoization
				dp_time = @elapsed _, _, memo_size = marginalize_with_memo(bn, params)
				push!(dp_times, dp_time)
				push!(memo_sizes, memo_size)

				# Calculate speedup
				speedup = standard_time / dp_time
				push!(speedups, speedup)

				# Print results
				@info "$name network (nodes: $node_count)" standard_time dp_time speedup memo_size

				# Verify correctness (results should match)
				_, logp1 = marginalize_without_memo(bn, params)
				_, logp2, _ = marginalize_with_memo(bn, params)
				@test isapprox(logp1, logp2, rtol = 1e-10)
			end

			# Summarize results
			network_names = [name for (name, _) in networks]
			@info "Comparative Performance Summary" network_names node_counts standard_times dp_times speedups memo_sizes

			# The memoization always gives correct results
			# In some cases, memoization might have overhead that exceeds benefits for smaller problems
			# or for first runs (without JIT warmup)
			@info "Performance ratios" network_names speedups

			# The memo size should be related to the structure complexity
			# Compare memo size to node count to see efficiency of memoization
			memo_ratios = memo_sizes ./ (2 .^ node_counts)
			@info "Memo size as fraction of total possible states" network_names memo_ratios

			# All memo sizes should be less than theoretical maximum states
			@test all(memo_sizes .< 2 .* (2 .^ node_counts))
		end
	end
end

using BenchmarkTools

function run_all_strategies(bn, params)
    # Warmup for JIT
    marginalize_without_memo(bn, params)
    evaluate_with_marginalization(bn, params; caching_strategy = :full_env)
    evaluate_with_marginalization(bn, params; caching_strategy = :minimal_key)

    # Naive
    t_naive = @belapsed marginalize_without_memo($bn, $params)
    _, logp_naive = marginalize_without_memo(bn, params)

    # Full env
    t_full = @belapsed evaluate_with_marginalization($bn, $params; caching_strategy = :full_env)
    _, logp_full = evaluate_with_marginalization(bn, params; caching_strategy = :full_env)

    # Minimal key
    t_min = @belapsed evaluate_with_marginalization($bn, $params; caching_strategy = :minimal_key)
    _, logp_min = evaluate_with_marginalization(bn, params; caching_strategy = :minimal_key)

    # Memo sizes
    function get_memo_size(strategy)
        memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
        minimal_keys = strategy == :minimal_key ? _precompute_minimal_cache_keys(bn) : nothing
        _ = JuliaBUGS.ProbabilisticGraphicalModels._marginalize_recursive(
            bn, deepcopy(bn.evaluation_env), topological_sort_by_dfs(bn.graph), params, 1,
            bn.transformed_var_lengths, memo, strategy, minimal_keys,
        )
        return length(memo)
    end

    memo_full = get_memo_size(:full_env)
    memo_min = get_memo_size(:minimal_key)

    # Check correctness
    @test isapprox(logp_naive, logp_full, rtol = 1e-10)
    @test isapprox(logp_naive, logp_min, rtol = 1e-10)

    return (t_naive, t_full, t_min, memo_full, memo_min)
end

function print_comprehensive_table(rows, header)
	println(header)
	println("| Network | Size | Naive (s) | FullEnv (s) | MinKey (s) | FullEnv Memo | MinKey Memo | FullEnv Speedup | MinKey Speedup |")
	println("|---------|------|-----------|-------------|------------|--------------|-------------| -----------------|---------------|")
	for row in rows
		@printf("| %-7s | %-4d | %9.4e | %11.4e | %10.4e | %12d | %11d | %15.2fx | %13.2fx |\n",
			row.network, row.size, row.t_naive, row.t_full, row.t_min, row.memo_full, row.memo_min,
			row.t_naive / row.t_full, row.t_naive / row.t_min)
	end
end

rows = []

# Chain networks
for n in [3, 5, 7, 9, 11, 13, 15, 17, 19]
	bn = create_chain_network(n)
	params = Float64[]
	t_naive, t_full, t_min, memo_full, memo_min = run_all_strategies(bn, params)
	push!(rows, (network = "Chain", size = n, t_naive = t_naive, t_full = t_full, t_min = t_min,
		memo_full = memo_full, memo_min = memo_min))
end

# Tree networks
for depth in [2, 3, 4]
	bn = create_tree_network(depth)
	params = Float64[]
	n_nodes = 2^depth - 1
	t_naive, t_full, t_min, memo_full, memo_min = run_all_strategies(bn, params)
	push!(rows, (network = "Tree", size = n_nodes, t_naive = t_naive, t_full = t_full, t_min = t_min,
		memo_full = memo_full, memo_min = memo_min))
end

println("\n# Tree Network Memoization Times for Large Depths")
println("| Depth | Nodes | MinKey Time (s) | Memo Size |")
println("|-------|-------|-----------------|-----------|")
for depth in [5]
	bn = create_tree_network(depth)
	params = Float64[]
	n_nodes = 2^depth - 1
	# Warmup
	_, _, _ = marginalize_with_memo(bn, params)
	# Time only the DP/memoized approach
	min_time = @elapsed _, _, memo_size = marginalize_with_memo(bn, params)
	@printf("| %5d | %5d | %15.4f | %9d |\n", depth, n_nodes, min_time, memo_size)
end


# Grid networks
for (w, h) in [(2, 2), (3, 3), (4, 4), (5, 5)]
	bn = create_grid_network(w, h)
	params = Float64[]
	n_nodes = w * h
	t_naive, t_full, t_min, memo_full, memo_min = run_all_strategies(bn, params)
	push!(rows, (network = "Grid", size = n_nodes, t_naive = t_naive, t_full = t_full, t_min = t_min,
		memo_full = memo_full, memo_min = memo_min))
end

print_comprehensive_table(rows, "# Memoization Strategy Comparison\n")

function create_hmm_network(n_states::Int, seq_length::Int)
	bn = BayesianNetwork{VarName}()

	# Hidden states and observation variables
	z_vars = [VarName(Symbol("z$t")) for t in 1:seq_length]
	x_vars = [VarName(Symbol("x$t")) for t in 1:seq_length]

	# Initialize tracking variables
	all_vars = Dict{Symbol, Any}()
	loop_vars = Dict{VarName, NamedTuple}()

	# Initialize with default values
	for t in 1:seq_length
		all_vars[Symbol("z$t")] = 1      # Default to first state
		all_vars[Symbol("x$t")] = 0.0    # Observation placeholder
		loop_vars[z_vars[t]] = (;)
		loop_vars[x_vars[t]] = (;)
	end

	# Add first hidden state node
	add_stochastic_vertex!(bn, z_vars[1],
		(_, _) -> Categorical(ones(n_states) / n_states), false, :discrete)

	# Add subsequent hidden state nodes with dependencies
	for t in 2:seq_length
		add_stochastic_vertex!(bn, z_vars[t],
			(env, _) -> begin
				# Previous state value
				prev_state = AbstractPPL.get(env, z_vars[t-1])
				# For simplicity using uniform transition probabilities
				return Categorical(ones(n_states) / n_states)
			end,
			false, :discrete)
		add_edge!(bn, z_vars[t-1], z_vars[t])
	end

	# Add observation nodes
	for t in 1:seq_length
		add_stochastic_vertex!(bn, x_vars[t],
			(env, _) -> begin
				# Current state value
				state = AbstractPPL.get(env, z_vars[t])
				# Emission model: Normal distribution centered at state value
				return Normal(Float64(state), 1.0)
			end,
			true, :continuous)
		add_edge!(bn, z_vars[t], x_vars[t])
	end

	# Create evaluation environment
	eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

	# Return final network
	BayesianNetwork(
		bn.graph,
		bn.names,
		bn.names_to_ids,
		eval_env,
		loop_vars,
		bn.distributions,
		bn.deterministic_functions,
		bn.stochastic_ids,
		bn.deterministic_ids,
		bn.is_stochastic,
		bn.is_observed,
		bn.node_types,
		Dict{VarName, Int}(),  # Use VarName type for consistency
		0,
	)
end
all_results = []  # Add this line to collect all results

function create_hmm_network(n_states::Int, seq_length::Int)
	bn = BayesianNetwork{VarName}()

	# Hidden states and observation variables
	z_vars = [VarName(Symbol("z$t")) for t in 1:seq_length]
	x_vars = [VarName(Symbol("x$t")) for t in 1:seq_length]

	# Initialize tracking variables
	all_vars = Dict{Symbol, Any}()
	loop_vars = Dict{VarName, NamedTuple}()

	# Initialize with default values
	for t in 1:seq_length
		all_vars[Symbol("z$t")] = 1      # Default to first state
		all_vars[Symbol("x$t")] = 0.0    # Observation placeholder
		loop_vars[z_vars[t]] = (;)
		loop_vars[x_vars[t]] = (;)
	end

	# Add first hidden state node
	add_stochastic_vertex!(bn, z_vars[1],
		(_, _) -> Categorical(ones(n_states) / n_states), false, :discrete)

	# Add subsequent hidden state nodes with dependencies
	for t in 2:seq_length
		add_stochastic_vertex!(bn, z_vars[t],
			(env, _) -> begin
				# Previous state value
				prev_state = AbstractPPL.get(env, z_vars[t-1])
				# For simplicity using uniform transition probabilities
				return Categorical(ones(n_states) / n_states)
			end,
			false, :discrete)
		add_edge!(bn, z_vars[t-1], z_vars[t])
	end

	# Add observation nodes
	for t in 1:seq_length
		add_stochastic_vertex!(bn, x_vars[t],
			(env, _) -> begin
				# Current state value
				state = AbstractPPL.get(env, z_vars[t])
				# Emission model: Normal distribution centered at state value
				return Normal(Float64(state), 1.0)
			end,
			true, :continuous)
		add_edge!(bn, z_vars[t], x_vars[t])
	end

	# Create evaluation environment
	eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

	# Return final network
	BayesianNetwork(
		bn.graph,
		bn.names,
		bn.names_to_ids,
		eval_env,
		loop_vars,
		bn.distributions,
		bn.deterministic_functions,
		bn.stochastic_ids,
		bn.deterministic_ids,
		bn.is_stochastic,
		bn.is_observed,
		bn.node_types,
		Dict{VarName, Int}(),  # Use VarName type for consistency
		0,
	)
end

@testset "HMM Networks" begin
	# Store results for final analysis
	hmm_results = []
	# Test different configurations of HMMs
	hmm_configs = [(2, 4), (3, 3), (2, 5)]

	for (n_states, seq_length) in hmm_configs
		# Create the HMM network
		bn = create_hmm_network(n_states, seq_length)
		network_name = "HMM (states=$n_states, length=$seq_length)"

		# Run the comparison test
		results = run_comparison_simple(bn, network_name)

		# Use @test_broken for parent-based since it's known to fail for HMMs
		@test_broken results.parent.correct
		@test results.discrete.correct
		@test results.full_env.correct
		@test results.minkey.correct  # Add minimal key correctness test

		# Store results for consolidated output
		theoretical_states = n_states^seq_length
		push!(
			hmm_results,
			Dict(
				:network => network_name,
				:n_states => n_states,
				:seq_length => seq_length,
				:no_memo_time => results.no_memo_time,
				:parent_time => results.parent.time,
				:discrete_time => results.discrete.time,
				:full_env_time => results.full_env.time,
				:minkey_time => results.minkey.time,  # Add minimal key time
				:parent_speedup => results.no_memo_time / results.parent.time,
				:discrete_speedup => results.no_memo_time / results.discrete.time,
				:full_env_speedup => results.no_memo_time / results.full_env.time,
				:minkey_speedup => results.no_memo_time / results.minkey.time,  # Add minimal key speedup
				:parent_size => results.parent.size,
				:discrete_size => results.discrete.size,
				:full_env_size => results.full_env.size,
				:minkey_size => results.minkey.size,  # Add minimal key memo size
				:theoretical_states => theoretical_states,
				:parent_correct => results.parent.correct,
				:discrete_correct => results.discrete.correct,
				:full_env_correct => results.full_env.correct,
				:minkey_correct => results.minkey.correct,  # Add minimal key correctness
			),
		)
	end

	# ---------- CONSOLIDATED OUTPUT FOR HMM NETWORKS ----------
	println("\n\n=== HMM NETWORKS MEMOIZATION PERFORMANCE ===")
	println("Configuration    | Strategy      | Speedup | Memo Size | Memo/States Ratio")
	println("-----------------|---------------|---------|-----------|----------------")

	for result in hmm_results
		config = "$(result[:n_states])×$(result[:seq_length])"

		# Calculate ratios
		parent_ratio = result[:parent_size] / result[:theoretical_states] * 100
		discrete_ratio = result[:discrete_size] / result[:theoretical_states] * 100
		full_env_ratio = result[:full_env_size] / result[:theoretical_states] * 100
		minkey_ratio = result[:minkey_size] / result[:theoretical_states] * 100  # Add minimal key ratio

		# Print results for each strategy
		println(rpad("HMM $config", 16), " | Parent-based  | ",
			@sprintf("%7.2fx", result[:parent_speedup]), " | ",
			@sprintf("%9d", result[:parent_size]), " | ",
			@sprintf("%7.2f%%", parent_ratio),
			result[:parent_correct] ? " ✓" : " ✗")
		println(rpad("HMM $config", 16), " | Discrete-only | ",
			@sprintf("%7.2fx", result[:discrete_speedup]), " | ",
			@sprintf("%9d", result[:discrete_size]), " | ",
			@sprintf("%7.2f%%", discrete_ratio),
			result[:discrete_correct] ? " ✓" : " ✗")
		println(rpad("HMM $config", 16), " | Full env      | ",
			@sprintf("%7.2fx", result[:full_env_speedup]), " | ",
			@sprintf("%9d", result[:full_env_size]), " | ",
			@sprintf("%7.2f%%", full_env_ratio),
			result[:full_env_correct] ? " ✓" : " ✗")
		println(rpad("HMM $config", 16), " | Minimal key   | ",  # Add minimal key output
			@sprintf("%7.2fx", result[:minkey_speedup]), " | ",
			@sprintf("%9d", result[:minkey_size]), " | ",
			@sprintf("%7.2f%%", minkey_ratio),
			result[:minkey_correct] ? " ✓" : " ✗")
	end

	println("\n=== HMM NETWORKS AVERAGE PERFORMANCE ===")
	println("Strategy      | Avg Speedup | Avg Memo/States | Correctness")
	println("--------------|-------------|----------------|------------")

	# Calculate averages across all HMM tests
	avg_parent_speedup = mean([r[:parent_speedup] for r in hmm_results])
	avg_discrete_speedup = mean([r[:discrete_speedup] for r in hmm_results])
	avg_full_env_speedup = mean([r[:full_env_speedup] for r in hmm_results])
	avg_minkey_speedup = mean([r[:minkey_speedup] for r in hmm_results])  # Add minimal key average

	avg_parent_ratio = mean([r[:parent_size] / r[:theoretical_states] for r in hmm_results])
	avg_discrete_ratio = mean([r[:discrete_size] / r[:theoretical_states] for r in hmm_results])
	avg_full_env_ratio = mean([r[:full_env_size] / r[:theoretical_states] for r in hmm_results])
	avg_minkey_ratio = mean([r[:minkey_size] / r[:theoretical_states] for r in hmm_results])  # Add minimal key ratio

	parent_correct = all([r[:parent_correct] for r in hmm_results])
	discrete_correct = all([r[:discrete_correct] for r in hmm_results])
	full_env_correct = all([r[:full_env_correct] for r in hmm_results])
	minkey_correct = all([r[:minkey_correct] for r in hmm_results])  # Add minimal key correctness

	println(rpad("Parent-based", 13), " | ",
		@sprintf("%11.2fx", avg_parent_speedup), " | ",
		@sprintf("%16.2f%%", avg_parent_ratio * 100), " | ",
		parent_correct ? "Always correct" : "Never correct for HMMs")
	println(rpad("Discrete-only", 13), " | ",
		@sprintf("%11.2fx", avg_discrete_speedup), " | ",
		@sprintf("%16.2f%%", avg_discrete_ratio * 100), " | ",
		discrete_correct ? "Always correct" : "Sometimes fails")
	println(rpad("Full env", 13), " | ",
		@sprintf("%11.2fx", avg_full_env_speedup), " | ",
		@sprintf("%16.2f%%", avg_full_env_ratio * 100), " | ",
		full_env_correct ? "Always correct" : "Sometimes fails")
	println(rpad("Minimal key", 13), " | ",  # Add minimal key summary
		@sprintf("%11.2fx", avg_minkey_speedup), " | ",
		@sprintf("%16.2f%%", avg_minkey_ratio * 100), " | ",
		minkey_correct ? "Always correct" : "Sometimes fails")

	println("\n=== HMM SCALING ANALYSIS ===")
	println("States | Length | Theoretical States | Parent-based | Discrete-only | Full env | Minimal key")
	println("-------|--------|-------------------|--------------|---------------|----------|------------")

	# Sort by complexity for better analysis
	sort!(hmm_results, by = r -> r[:theoretical_states])

	for result in hmm_results
		println(
			@sprintf("%6d", result[:n_states]), " | ",
			@sprintf("%6d", result[:seq_length]), " | ",
			@sprintf("%18d", result[:theoretical_states]), " | ",
			@sprintf("%12d", result[:parent_size]), " | ",
			@sprintf("%13d", result[:discrete_size]), " | ",
			@sprintf("%8d", result[:full_env_size]), " | ",
			@sprintf("%11d", result[:minkey_size])  # Add minimal key column
		)
	end

	# Print relationship with sequence length
	println("\n=== HMM MEMO SIZE GROWTH WITH SEQUENCE LENGTH ===")
	println("For binary state HMMs (2 states):")
	binary_hmms = filter(r -> r[:n_states] == 2, hmm_results)
	sort!(binary_hmms, by = r -> r[:seq_length])

	if length(binary_hmms) > 1
		println("Sequence Length | Parent-based | Discrete-only | Full env | Minimal key")
		println("---------------|--------------|---------------|----------|------------")

		for result in binary_hmms
			println(
				@sprintf("%15d", result[:seq_length]), " | ",
				@sprintf("%12d", result[:parent_size]), " | ",
				@sprintf("%13d", result[:discrete_size]), " | ",
				@sprintf("%8d", result[:full_env_size]), " | ",
				@sprintf("%11d", result[:minkey_size])  # Add minimal key column
			)
		end
	else
		println("Insufficient binary HMM data points for growth analysis")
	end

	# Add minimal key specific analysis
	println("\n=== MINIMAL KEY vs FULL ENVIRONMENT COMPARISON ===")
	println("Configuration    | MinKey Size | FullEnv Size | Memory Improvement")
	println("-----------------|-------------|--------------|------------------")
	
	for result in hmm_results
		config = "$(result[:n_states])×$(result[:seq_length])"
		improvement = result[:full_env_size] / result[:minkey_size]
		println(rpad("HMM $config", 16), " | ",
			@sprintf("%11d", result[:minkey_size]), " | ",
			@sprintf("%12d", result[:full_env_size]), " | ",
			@sprintf("%17.2fx", improvement))
	end

	avg_improvement = mean([r[:full_env_size] / r[:minkey_size] for r in hmm_results])
	println("\nAverage memory improvement (FullEnv/MinKey): $(round(avg_improvement, digits=2))x")
end

using BenchmarkTools
function run_comparison_simple(bn, network_name)
    params = Float64[]

    # Precompute minimal keys for minimal key strategy
    precomputed_minimal_keys = _precompute_minimal_cache_keys(bn)

    # Warmup runs
    marginalize_without_memo(deepcopy(bn), params)
    parent_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
    _ = _marginalize_recursive(
        deepcopy(bn), deepcopy(bn.evaluation_env),
        topological_sort_by_dfs(bn.graph), params, 1,
        bn.transformed_var_lengths, parent_memo, :parent_based, nothing
    )
    discrete_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
    _ = _marginalize_recursive(
        deepcopy(bn), deepcopy(bn.evaluation_env),
        topological_sort_by_dfs(bn.graph), params, 1,
        bn.transformed_var_lengths, discrete_memo, :discrete_only, nothing
    )
    full_env_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
    _ = _marginalize_recursive(
        deepcopy(bn), deepcopy(bn.evaluation_env),
        topological_sort_by_dfs(bn.graph), params, 1,
        bn.transformed_var_lengths, full_env_memo, :full_env, nothing
    )
    minkey_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
    _ = _marginalize_recursive(
        deepcopy(bn), deepcopy(bn.evaluation_env),
        topological_sort_by_dfs(bn.graph), params, 1,
        bn.transformed_var_lengths, minkey_memo, :minimal_key, precomputed_minimal_keys
    )

    # Get the baseline result for correctness comparison
    _, no_memo_logp = marginalize_without_memo(deepcopy(bn), params)

    # Benchmark the no-memo version
    b1 = @benchmark marginalize_without_memo($(deepcopy(bn)), $params)
    no_memo_time = median(b1).time / 1e9

    # Parent-based memoization
    b2 = @benchmark begin
        parent_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
        parent_logp = _marginalize_recursive(
            $(deepcopy(bn)),
            $(deepcopy(bn.evaluation_env)),
            topological_sort_by_dfs($(bn.graph)),
            $params, 1, $(bn.transformed_var_lengths),
            parent_memo, :parent_based, nothing
        )
    end
    parent_time = median(b2).time / 1e9

    # Run once outside benchmark
    parent_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
    parent_logp = _marginalize_recursive(
        deepcopy(bn), deepcopy(bn.evaluation_env),
        topological_sort_by_dfs(bn.graph), params, 1,
        bn.transformed_var_lengths, parent_memo, :parent_based, nothing
    )

    # Discrete-only memoization
    b3 = @benchmark begin
        discrete_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
        discrete_logp = _marginalize_recursive(
            $(deepcopy(bn)),
            $(deepcopy(bn.evaluation_env)),
            topological_sort_by_dfs($(bn.graph)),
            $params, 1, $(bn.transformed_var_lengths),
            discrete_memo, :discrete_only, nothing
        )
    end
    discrete_time = median(b3).time / 1e9

    # Run once outside benchmark
    discrete_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
    discrete_logp = _marginalize_recursive(
        deepcopy(bn), deepcopy(bn.evaluation_env),
        topological_sort_by_dfs(bn.graph), params, 1,
        bn.transformed_var_lengths, discrete_memo, :discrete_only, nothing
    )

    # Full-env memoization
    b4 = @benchmark begin
        full_env_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
        full_env_logp = _marginalize_recursive(
            $(deepcopy(bn)),
            $(deepcopy(bn.evaluation_env)),
            topological_sort_by_dfs($(bn.graph)),
            $params, 1, $(bn.transformed_var_lengths),
            full_env_memo, :full_env, nothing
        )
    end
    full_env_time = median(b4).time / 1e9

    # Run once outside benchmark
    full_env_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
    full_env_logp = _marginalize_recursive(
        deepcopy(bn), deepcopy(bn.evaluation_env),
        topological_sort_by_dfs(bn.graph), params, 1,
        bn.transformed_var_lengths, full_env_memo, :full_env, nothing
    )

    # Minimal key memoization
    b5 = @benchmark begin
        minkey_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
        minkey_logp = _marginalize_recursive(
            $(deepcopy(bn)),
            $(deepcopy(bn.evaluation_env)),
            topological_sort_by_dfs($(bn.graph)),
            $params, 1, $(bn.transformed_var_lengths),
            minkey_memo, :minimal_key, $precomputed_minimal_keys
        )
    end
    minkey_time = median(b5).time / 1e9

    # Run once outside benchmark
    minkey_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
    minkey_logp = _marginalize_recursive(
        deepcopy(bn), deepcopy(bn.evaluation_env),
        topological_sort_by_dfs(bn.graph), params, 1,
        bn.transformed_var_lengths, minkey_memo, :minimal_key, precomputed_minimal_keys
    )

    # Calculate correctness
    parent_correct = isapprox(parent_logp, no_memo_logp, rtol = 1e-10)
    discrete_correct = isapprox(discrete_logp, no_memo_logp, rtol = 1e-10)
    full_env_correct = isapprox(full_env_logp, no_memo_logp, rtol = 1e-10)
    minkey_correct = isapprox(minkey_logp, no_memo_logp, rtol = 1e-10)

    # Rest of the function remains the same...
    discrete_count = sum(bn.node_types .== :discrete)
    theoretical_states = discrete_count > 0 ? 2^discrete_count : 0

    @info "$network_name BenchmarkTools Results" begin
        parent_time = parent_time
        discrete_time = discrete_time
        full_env_time = full_env_time
        minkey_time = minkey_time
        parent_speedup = no_memo_time / parent_time
        discrete_speedup = no_memo_time / discrete_time
        full_env_speedup = no_memo_time / full_env_time
        minkey_speedup = no_memo_time / minkey_time
        parent_memo_size = length(parent_memo)
        discrete_memo_size = length(discrete_memo)
        full_env_memo_size = length(full_env_memo)
        minkey_memo_size = length(minkey_memo)
        parent_correct = parent_correct
        discrete_correct = discrete_correct
        full_env_correct = full_env_correct
        minkey_correct = minkey_correct
    end

    return (
        no_memo_time = no_memo_time,
        parent = (time = parent_time, size = length(parent_memo), correct = parent_correct),
        discrete = (time = discrete_time, size = length(discrete_memo), correct = discrete_correct),
        full_env = (time = full_env_time, size = length(full_env_memo), correct = full_env_correct),
        minkey = (time = minkey_time, size = length(minkey_memo), correct = minkey_correct),
    )
end


function run_comparison_benchmarktools(bn, network_name)
	params = Float64[]

	# Get baseline result for correctness checking
	_, no_memo_logp = marginalize_without_memo(deepcopy(bn), params)

	# Create local copies of needed values to ensure they're properly captured
	local_env = deepcopy(bn.evaluation_env)
	local_graph = bn.graph
	local_var_lengths = bn.transformed_var_lengths

	# No memoization
	b1 = @benchmarkable marginalize_without_memo($(deepcopy(bn)), $params)

	# Parent-based memoization
	b2 = @benchmarkable begin
		memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			$(deepcopy(bn)),
			$(deepcopy(local_env)),
			topological_sort_by_dfs($local_graph),
			$params, 1, $local_var_lengths,
			memo, :parent_based,
		)
	end

	# Discrete-only memoization
	b3 = @benchmarkable begin
		memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			$(deepcopy(bn)),
			$(deepcopy(local_env)),
			topological_sort_by_dfs($local_graph),
			$params, 1, $local_var_lengths,
			memo, :discrete_only,
		)
	end

	# Full-env memoization
	b4 = @benchmarkable begin
		memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			$(deepcopy(bn)),
			$(deepcopy(local_env)),
			topological_sort_by_dfs($local_graph),
			$params, 1, $local_var_lengths,
			memo, :full_env,
		)
	end

	# Run benchmarks
	no_memo_result = run(b1, samples = 10, seconds = 1)
	parent_result = run(b2, samples = 10, seconds = 1)
	discrete_result = run(b3, samples = 10, seconds = 1)
	full_env_result = run(b4, samples = 10, seconds = 1)

	# Extract timing results
	no_memo_time = median(no_memo_result).time / 1e9  # Convert to seconds
	parent_time = median(parent_result).time / 1e9
	discrete_time = median(discrete_result).time / 1e9
	full_env_time = median(full_env_result).time / 1e9

	# Run once outside benchmark to get actual memo sizes and check correctness

	# Parent-based
	parent_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
	parent_logp = _marginalize_recursive(
		deepcopy(bn), deepcopy(bn.evaluation_env),
		topological_sort_by_dfs(bn.graph), params, 1,
		bn.transformed_var_lengths, parent_memo, :parent_based,
	)

	# Discrete-only
	discrete_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
	discrete_logp = _marginalize_recursive(
		deepcopy(bn), deepcopy(bn.evaluation_env),
		topological_sort_by_dfs(bn.graph), params, 1,
		bn.transformed_var_lengths, discrete_memo, :discrete_only,
	)

	# Full-env
	full_env_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
	full_env_logp = _marginalize_recursive(
		deepcopy(bn), deepcopy(bn.evaluation_env),
		topological_sort_by_dfs(bn.graph), params, 1,
		bn.transformed_var_lengths, full_env_memo, :full_env,
	)

	# Check correctness
	parent_correct = isapprox(parent_logp, no_memo_logp, rtol = 1e-10)
	discrete_correct = isapprox(discrete_logp, no_memo_logp, rtol = 1e-10)
	full_env_correct = isapprox(full_env_logp, no_memo_logp, rtol = 1e-10)

	# Count discrete variables
	discrete_count = sum(bn.node_types .== :discrete)
	theoretical_states = discrete_count > 0 ? 2^discrete_count : 0

	push!(all_results, Dict(
		:network => network_name,
		:network_type => contains(network_name, "Chain") ? "Chain" :
						 contains(network_name, "Tree") ? "Tree" :
						 contains(network_name, "HMM") ? "HMM" : "Grid",
		:no_memo_time => no_memo_time,
		# Add the rest of the fields...
	))

	# Return results
	return (
		no_memo_time = no_memo_time,
		parent = (time = parent_time, size = length(parent_memo), correct = parent_correct),
		discrete = (time = discrete_time, size = length(discrete_memo), correct = discrete_correct),
		full_env = (time = full_env_time, size = length(full_env_memo), correct = full_env_correct),
	)
end

function run_comparison_benchmark(bn, network_name)
	params = Float64[]

	# Get baseline result for correctness checking
	_, no_memo_logp = marginalize_without_memo(deepcopy(bn), params)

	# Create local copies for benchmarking
	local_env = deepcopy(bn.evaluation_env)
	local_graph = bn.graph
	local_var_lengths = bn.transformed_var_lengths

	# Benchmark no memoization
	b_no_memo = @benchmarkable marginalize_without_memo($(deepcopy(bn)), $params)
	no_memo_result = run(b_no_memo, samples = 5, seconds = 1)
	no_memo_time = median(no_memo_result).time / 1e9  # Convert to seconds

	# Benchmark parent-based memoization
	b_parent = @benchmarkable begin
		memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			$(deepcopy(bn)),
			$(deepcopy(local_env)),
			topological_sort_by_dfs($local_graph),
			$params, 1, $local_var_lengths,
			memo, :parent_based,
		)
	end
	parent_result = run(b_parent, samples = 5, seconds = 1)
	parent_time = median(parent_result).time / 1e9

	# Get accurate memo size and correctness with a separate run
	parent_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
	parent_logp = _marginalize_recursive(
		deepcopy(bn), deepcopy(bn.evaluation_env),
		topological_sort_by_dfs(bn.graph), params, 1,
		bn.transformed_var_lengths, parent_memo, :parent_based,
	)

	# Benchmark discrete-only memoization
	b_discrete = @benchmarkable begin
		memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			$(deepcopy(bn)),
			$(deepcopy(local_env)),
			topological_sort_by_dfs($local_graph),
			$params, 1, $local_var_lengths,
			memo, :discrete_only,
		)
	end
	discrete_result = run(b_discrete, samples = 5, seconds = 1)
	discrete_time = median(discrete_result).time / 1e9

	# Get accurate memo size and correctness
	discrete_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
	discrete_logp = _marginalize_recursive(
		deepcopy(bn), deepcopy(bn.evaluation_env),
		topological_sort_by_dfs(bn.graph), params, 1,
		bn.transformed_var_lengths, discrete_memo, :discrete_only,
	)

	# Benchmark full-env memoization
	b_full_env = @benchmarkable begin
		memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			$(deepcopy(bn)),
			$(deepcopy(local_env)),
			topological_sort_by_dfs($local_graph),
			$params, 1, $local_var_lengths,
			memo, :full_env,
		)
	end
	full_env_result = run(b_full_env, samples = 5, seconds = 1)
	full_env_time = median(full_env_result).time / 1e9

	# Get accurate memo size and correctness
	full_env_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
	full_env_logp = _marginalize_recursive(
		deepcopy(bn), deepcopy(bn.evaluation_env),
		topological_sort_by_dfs(bn.graph), params, 1,
		bn.transformed_var_lengths, full_env_memo, :full_env,
	)

	# Check correctness
	parent_correct = isapprox(parent_logp, no_memo_logp, rtol = 1e-10)
	discrete_correct = isapprox(discrete_logp, no_memo_logp, rtol = 1e-10)
	full_env_correct = isapprox(full_env_logp, no_memo_logp, rtol = 1e-10)

	# Count discrete variables
	discrete_count = sum(bn.node_types .== :discrete)

	# For HMMs, theoretical states is more accurately n_states^seq_length
	# But for other networks, use 2^discrete_count as a reasonable approximation
	theoretical_states = if contains(network_name, "HMM")
		# Try to extract states and length from name
		states_match = match(r"states=(\d+)", network_name)
		length_match = match(r"length=(\d+)", network_name)

		# Default to 2 states if not specified
		states = states_match === nothing ? 2 : parse(Int, states_match.captures[1])

		# Length must be specified
		if length_match === nothing
			error("HMM network name must include length=X pattern")
		end

		length = parse(Int, length_match.captures[1])
		states^length
	else
		2^discrete_count
	end

	# Add to global results array
	push!(
		all_results,
		Dict(
			:network => network_name,
			:network_type => contains(network_name, "Chain") ? "Chain" :
							 contains(network_name, "Tree") ? "Tree" :
							 contains(network_name, "HMM") ? "HMM" : "Grid",
			:no_memo_time => no_memo_time,
			:parent_time => parent_time,
			:discrete_time => discrete_time,
			:full_env_time => full_env_time,
			:parent_speedup => no_memo_time / parent_time,
			:discrete_speedup => no_memo_time / discrete_time,
			:full_env_speedup => no_memo_time / full_env_time,
			:parent_memo_size => length(parent_memo),
			:discrete_memo_size => length(discrete_memo),
			:full_env_memo_size => length(full_env_memo),
			:parent_correct => parent_correct,
			:discrete_correct => discrete_correct,
			:full_env_correct => full_env_correct,
			:discrete_vars => discrete_count,
			:theoretical_states => theoretical_states,
		),
	)

	# Log results
	@info "$network_name Benchmark Results" begin
		parent_time = parent_time
		discrete_time = discrete_time
		full_env_time = full_env_time
		parent_speedup = no_memo_time / parent_time
		discrete_speedup = no_memo_time / discrete_time
		full_env_speedup = no_memo_time / full_env_time
		parent_memo_size = length(parent_memo)
		discrete_memo_size = length(discrete_memo)
		full_env_memo_size = length(full_env_memo)
		parent_correct = parent_correct
		discrete_correct = discrete_correct
		full_env_correct = full_env_correct
	end

	# Return results in same format as original function
	return (
		no_memo_time = no_memo_time,
		parent = (time = parent_time, size = length(parent_memo), correct = parent_correct),
		discrete = (time = discrete_time, size = length(discrete_memo), correct = discrete_correct),
		full_env = (time = full_env_time, size = length(full_env_memo), correct = full_env_correct),
	)
end

using BenchmarkTools
using Printf

function benchmark_hmm_scaling()
	println("\n=== HMM LENGTH SCALING TEST (BenchmarkTools) ===")
	println("Sequence Length | Strategy      | Speedup | Memo Size | Memo/States")
	println("---------------|---------------|---------|-----------|----------")

	# Test increasingly long sequences with binary states
	for seq_len in [5, 10, 15, 20]
		# Create network with 2 states
		bn = create_hmm_network(2, seq_len)
		theoretical_states = 2^seq_len

		# Create local copies for benchmarking
		local_env = deepcopy(bn.evaluation_env)
		local_graph = bn.graph
		local_var_lengths = bn.transformed_var_lengths
		params = Float64[]

		# Get baseline for correctness checking
		_, baseline_logp = marginalize_without_memo(deepcopy(bn), params)

		# Benchmark no memoization
		no_memo_bench = @benchmark marginalize_without_memo($(deepcopy(bn)), $params)
		no_memo_time = median(no_memo_bench).time / 1e9  # Convert to seconds

		# Benchmark and collect data for each strategy
		function benchmark_strategy(strategy_symbol)
			# Define the benchmark
			bench = @benchmarkable begin
				memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
				_marginalize_recursive(
					$(deepcopy(bn)),
					$(deepcopy(local_env)),
					topological_sort_by_dfs($local_graph),
					$params, 1, $local_var_lengths,
					memo, $strategy_symbol,
				)
			end

			# Set parameters and run
			bench_result = run(BenchmarkTools.tune!(bench))
			strategy_time = median(bench_result).time / 1e9

			# Run once more to get accurate memo size and verify correctness
			memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
			strategy_logp = _marginalize_recursive(
				deepcopy(bn), deepcopy(bn.evaluation_env),
				topological_sort_by_dfs(bn.graph), params, 1,
				bn.transformed_var_lengths, memo, strategy_symbol,
			)

			return (
				time = strategy_time,
				size = length(memo),
				correct = isapprox(strategy_logp, baseline_logp, rtol = 1e-10),
			)
		end

		# Run each strategy
		parent_result = benchmark_strategy(:parent_based)
		discrete_result = benchmark_strategy(:discrete_only)
		full_env_result = benchmark_strategy(:full_env)

		# Calculate speedups
		parent_speedup = no_memo_time / parent_result.time
		discrete_speedup = no_memo_time / discrete_result.time
		full_env_speedup = no_memo_time / full_env_result.time

		# Calculate ratios
		parent_ratio = parent_result.size / theoretical_states * 100
		discrete_ratio = discrete_result.size / theoretical_states * 100
		full_env_ratio = full_env_result.size / theoretical_states * 100

		# Print results
		print_strategy_result(seq_len, "Parent-based", parent_speedup, parent_result.size,
			parent_ratio, parent_result.correct)
		print_strategy_result(seq_len, "Discrete-only", discrete_speedup, discrete_result.size,
			discrete_ratio, discrete_result.correct)
		print_strategy_result(seq_len, "Full env", full_env_speedup, full_env_result.size,
			full_env_ratio, full_env_result.correct)
	end
end

# Helper function to print results in a consistent format
function print_strategy_result(length, strategy, speedup, size, ratio, correct)
	println(@sprintf("%-15d", length), "| ", rpad(strategy, 12), " | ",
		@sprintf("%7.2fx", speedup), " | ",
		@sprintf("%9d", size), " | ",
		@sprintf("%9.2f%%", ratio),
		correct ? " ✓" : " ✗")
end
# Helper function to print results in a consistent format

function run_all_scaling_tests()
	# Start with HMM length scaling (most important)
	println("\n======= MEMOIZATION STRATEGY SCALING TESTS =======")

	# Test HMM sequence length (key for showing crossover point)
	test_hmm_length_scaling_simplified()

	# # Test HMM state count impact
	test_hmm_state_count()

	# # Test tree depth scaling
	# test_tree_depth_scaling()

	# # Test grid size scaling
	# test_grid_size_scaling()

end
run_all_scaling_tests()

benchmark_hmm_scaling()

using BenchmarkTools
using Printf

# Helper function to print results in a consistent format
function print_strategy_result(config, strategy, speedup, size, ratio, correct)
	println(rpad(config, 15), "| ", rpad(strategy, 12), " | ",
		@sprintf("%7.2fx", speedup), " | ",
		@sprintf("%9d", size), " | ",
		@sprintf("%9.2f%%", ratio),
		correct ? " ✓" : " ✗")
end


function run_chain_scaling_test()
	println("\n=== CHAIN LENGTH SCALING TEST ===")
	println("Chain Length | Strategy      | Speedup | Memo Size | Memo/States Ratio")
	println("------------|---------------|---------|-----------|------------------")

	for chain_length in [5, 8, 12, 16, 20, 24]
		# Create the network
		bn = create_chain_network(chain_length)
		params = Float64[]
		theoretical_states = 2^chain_length

		# Get baseline result
		no_memo_time = @elapsed _, no_memo_logp = marginalize_without_memo(bn, params)

		# Parent-based
		parent_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		parent_time = @elapsed parent_logp = _marginalize_recursive(
			bn, deepcopy(bn.evaluation_env),
			topological_sort_by_dfs(bn.graph), params, 1,
			bn.transformed_var_lengths, parent_memo, :parent_based,
		)

		# Discrete-only
		discrete_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		discrete_time = @elapsed discrete_logp = _marginalize_recursive(
			bn, deepcopy(bn.evaluation_env),
			topological_sort_by_dfs(bn.graph), params, 1,
			bn.transformed_var_lengths, discrete_memo, :discrete_only,
		)

		# Full-env
		full_env_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		full_env_time = @elapsed full_env_logp = _marginalize_recursive(
			bn, deepcopy(bn.evaluation_env),
			topological_sort_by_dfs(bn.graph), params, 1,
			bn.transformed_var_lengths, full_env_memo, :full_env,
		)

		# Calculate speedups and ratios
		parent_speedup = no_memo_time / parent_time
		discrete_speedup = no_memo_time / discrete_time
		full_env_speedup = no_memo_time / full_env_time

		parent_ratio = length(parent_memo) / theoretical_states * 100
		discrete_ratio = length(discrete_memo) / theoretical_states * 100
		full_env_ratio = length(full_env_memo) / theoretical_states * 100

		# Check correctness
		parent_correct = isapprox(parent_logp, no_memo_logp, rtol = 1e-10)
		discrete_correct = isapprox(discrete_logp, no_memo_logp, rtol = 1e-10)
		full_env_correct = isapprox(full_env_logp, no_memo_logp, rtol = 1e-10)

		# Print results for each strategy
		println(@sprintf("%-12d", chain_length), " | Parent-based  | ",
			@sprintf("%7.2fx", parent_speedup), " | ",
			@sprintf("%9d", length(parent_memo)), " | ",
			@sprintf("%16.2f%%", parent_ratio),
			parent_correct ? " ✓" : " ✗")
		println(@sprintf("%-12d", chain_length), " | Discrete-only | ",
			@sprintf("%7.2fx", discrete_speedup), " | ",
			@sprintf("%9d", length(discrete_memo)), " | ",
			@sprintf("%16.2f%%", discrete_ratio),
			discrete_correct ? " ✓" : " ✗")
		println(@sprintf("%-12d", chain_length), " | Full env      | ",
			@sprintf("%7.2fx", full_env_speedup), " | ",
			@sprintf("%9d", length(full_env_memo)), " | ",
			@sprintf("%16.2f%%", full_env_ratio),
			full_env_correct ? " ✓" : " ✗")
	end
end

function run_robust_scaling_test()
	println("\n=== CHAIN LENGTH SCALING TEST (ROBUST) ===")
	println("Length | Strategy      | Time (ms) | Memo Size | Size/States")
	println("-------|---------------|-----------|-----------|------------")

	for length in [5, 8, 12, 16, 20]
		# Create the network
		bn = create_chain_network(length)
		params = Float64[]
		theoretical_states = 2^length

		# Run no memoization
		nomemo_fn = () -> marginalize_without_memo(deepcopy(bn), params)
		nomemo_result = @benchmark $nomemo_fn()
		nomemo_time_ms = median(nomemo_result).time / 1_000_000  # ns to ms

		# Set up parent-based test
		parent_fn = () -> begin
			memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
			_marginalize_recursive(
				deepcopy(bn), deepcopy(bn.evaluation_env),
				topological_sort_by_dfs(bn.graph), params, 1,
				bn.transformed_var_lengths, memo, :parent_based,
			)
		end

		# Set up discrete-only test
		discrete_fn = () -> begin
			memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
			_marginalize_recursive(
				deepcopy(bn), deepcopy(bn.evaluation_env),
				topological_sort_by_dfs(bn.graph), params, 1,
				bn.transformed_var_lengths, memo, :discrete_only,
			)
		end

		# Set up full-env test
		fullenv_fn = () -> begin
			memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
			_marginalize_recursive(
				deepcopy(bn), deepcopy(bn.evaluation_env),
				topological_sort_by_dfs(bn.graph), params, 1,
				bn.transformed_var_lengths, memo, :full_env,
			)
		end

		# Benchmark each strategy
		parent_result = @benchmark $parent_fn()
		discrete_result = @benchmark $discrete_fn()
		fullenv_result = @benchmark $fullenv_fn()

		# Convert to milliseconds
		parent_time_ms = median(parent_result).time / 1_000_000
		discrete_time_ms = median(discrete_result).time / 1_000_000
		fullenv_time_ms = median(fullenv_result).time / 1_000_000

		# Run once more to get memo sizes
		parent_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			deepcopy(bn), deepcopy(bn.evaluation_env),
			topological_sort_by_dfs(bn.graph), params, 1,
			bn.transformed_var_lengths, parent_memo, :parent_based,
		)

		discrete_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			deepcopy(bn), deepcopy(bn.evaluation_env),
			topological_sort_by_dfs(bn.graph), params, 1,
			bn.transformed_var_lengths, discrete_memo, :discrete_only,
		)

		fullenv_memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
		_marginalize_recursive(
			deepcopy(bn), deepcopy(bn.evaluation_env),
			topological_sort_by_dfs(bn.graph), params, 1,
			bn.transformed_var_lengths, fullenv_memo, :full_env,
		)

		# Calculate ratios
		parent_ratio = length(parent_memo) / theoretical_states * 100
		discrete_ratio = length(discrete_memo) / theoretical_states * 100
		fullenv_ratio = length(fullenv_memo) / theoretical_states * 100

		# Print results - showing absolute times instead of speedups
		println(@sprintf("%-6d", length), " | No memo       | ",
			@sprintf("%9.3f", nomemo_time_ms), " | ",
			@sprintf("%9s", "-"), " | ",
			@sprintf("%10s", "-"))
		println(@sprintf("%-6d", length), " | Parent-based  | ",
			@sprintf("%9.3f", parent_time_ms), " | ",
			@sprintf("%9d", length(parent_memo)), " | ",
			@sprintf("%9.2f%%", parent_ratio))
		println(@sprintf("%-6d", length), " | Discrete-only | ",
			@sprintf("%9.3f", discrete_time_ms), " | ",
			@sprintf("%9d", length(discrete_memo)), " | ",
			@sprintf("%9.2f%%", discrete_ratio))
		println(@sprintf("%-6d", length), " | Full env      | ",
			@sprintf("%9.3f", fullenv_time_ms), " | ",
			@sprintf("%9d", length(fullenv_memo)), " | ",
			@sprintf("%9.2f%%", fullenv_ratio))
	end
end

using Graphs
@testset "Moralization" begin
    # Test 1: Simple v-structure (A → C ← B)
    g1 = SimpleDiGraph(3)
    Graphs.add_edge!(g1, 1, 3)
    Graphs.add_edge!(g1, 2, 3)
    mg1 = moralize(g1)
    @test nv(mg1) == 3
    @test ne(mg1) == 3  # Corrected: A-B, A-C, B-C
    @test has_edge(mg1, 1, 2)  # Moral edge
    @test has_edge(mg1, 1, 3)  # Original edge
    @test has_edge(mg1, 2, 3)  # Original edge
    
    # Test 2: Chain structure (A → B → C)
    g2 = SimpleDiGraph(3)
    Graphs.add_edge!(g2, 1, 2)
    Graphs.add_edge!(g2, 2, 3)
    mg2 = moralize(g2)
    @test nv(mg2) == 3
    @test ne(mg2) == 2  # No moral edges needed
    @test has_edge(mg2, 1, 2)
    @test has_edge(mg2, 2, 3)
    
    # Test 3: Diamond structure
    g3 = SimpleDiGraph(4)
    Graphs.add_edge!(g3, 1, 2)
    Graphs.add_edge!(g3, 1, 3)
    Graphs.add_edge!(g3, 2, 4)
    Graphs.add_edge!(g3, 3, 4)
    mg3 = moralize(g3)
    @test nv(mg3) == 4
    @test ne(mg3) == 5  # Corrected: All original edges + moral edge between 2-3
    @test has_edge(mg3, 2, 3)  # Moral edge
    @test has_edge(mg3, 1, 2)
    @test has_edge(mg3, 1, 3)
    @test has_edge(mg3, 2, 4)
    @test has_edge(mg3, 3, 4)
    
    # Test 4: Complex structure with multiple v-structures
    g4 = SimpleDiGraph(5)
    Graphs.add_edge!(g4, 1, 3)
    Graphs.add_edge!(g4, 2, 3)
    Graphs.add_edge!(g4, 3, 4)
    Graphs.add_edge!(g4, 3, 5)
    mg4 = moralize(g4)
    @test nv(mg4) == 5
    @test ne(mg4) == 5  # Corrected: Original edges + moral edge between 1-2
    @test has_edge(mg4, 1, 2)  # Moral edge
    @test has_edge(mg4, 1, 3)
    @test has_edge(mg4, 2, 3)
    @test has_edge(mg4, 3, 4)
    @test has_edge(mg4, 3, 5)
end

@testset "Topological Sort Heuristics" begin
    # Create a diamond-shaped Bayesian Network
    bn = BayesianNetwork{Symbol}()
    
    # Add vertices and get their IDs
    a_id = add_stochastic_vertex!(bn, :A, nothing, false, :discrete)
    b_id = add_stochastic_vertex!(bn, :B, nothing, false, :discrete)
    c_id = add_stochastic_vertex!(bn, :C, nothing, false, :discrete)
    d_id = add_stochastic_vertex!(bn, :D, nothing, false, :continuous)  # Start unobserved
    
    # Add edges using vertex IDs
    Graphs.add_edge!(bn.graph, a_id, b_id)
    Graphs.add_edge!(bn.graph, a_id, c_id)
    Graphs.add_edge!(bn.graph, b_id, d_id)
    Graphs.add_edge!(bn.graph, c_id, d_id)
    
    # Create a new BayesianNetwork with D observed
    new_is_observed = copy(bn.is_observed)
    new_is_observed[d_id] = true
    
    new_evaluation_env = BangBang.setindex!!(bn.evaluation_env, 1.5, :D)
    
    bn_obs = BayesianNetwork(
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
        bn.transformed_param_length
    )
    
    # Test 1: DFS order
    dfs_order = topological_sort_with_heuristic(bn_obs, :dfs)
    @test length(dfs_order) == 4
    @test dfs_order[end] == d_id  # Observed node last
    
    # Test 2: MinDegree order
    min_deg_order = topological_sort_with_heuristic(bn_obs, :min_degree)
    @test length(min_deg_order) == 4
    @test min_deg_order[end] == d_id
    
    # Test 3: MinFill order
    min_fill_order = topological_sort_with_heuristic(bn_obs, :min_fill)
    @test length(min_fill_order) == 4
    @test min_fill_order[end] == d_id
    
    # Test 4: Verify orders are valid topological sorts
    function is_valid_topological_order(g, order)
        visited = falses(Graphs.nv(g))
        for v in order
            for parent in Graphs.inneighbors(g, v)
                if !visited[parent]
                    return false
                end
            end
            visited[v] = true
        end
        return true
    end
    
    @test is_valid_topological_order(bn_obs.graph, dfs_order)
    @test is_valid_topological_order(bn_obs.graph, min_deg_order)
    @test is_valid_topological_order(bn_obs.graph, min_fill_order)
    
    # Test 5: Compare orders for efficiency
    # MinFill should prioritize nodes that minimize fill-in edges
    # In diamond structure, MinFill should eliminate A first
    @test min_fill_order[1] == a_id
end

# Helper function to create VarName
function varname(sym::Symbol)
    return JuliaBUGS.VarName(sym)
end

function create_diamond_network()
    bn = BayesianNetwork{VarName}()
    
    # Create VarNames
    vn_A = varname(:A)
    vn_B = varname(:B)
    vn_C = varname(:C)
    vn_D = varname(:D)

    # Initial environment values
    init_env = (A = 0, B = 0, C = 0, D = 1.5)  # D is observed
    
    # Create loop_vars dictionary with empty NamedTuples
    loop_vars_dict = Dict{VarName, NamedTuple}(
        vn_A => (;),
        vn_B => (;),
        vn_C => (;),
        vn_D => (;)
    )
    
    # Add vertices with corrected distribution functions
    a_id = add_stochastic_vertex!(bn, vn_A, 
        (env, _) -> Bernoulli(0.4), false, :discrete)
    b_id = add_stochastic_vertex!(bn, vn_B, 
        (env, _) -> Bernoulli(AbstractPPL.get(env, vn_A) == 1 ? 0.7 : 0.3),  # FIXED
        false, :discrete)
    c_id = add_stochastic_vertex!(bn, vn_C, 
        (env, _) -> Bernoulli(AbstractPPL.get(env, vn_A) == 1 ? 0.6 : 0.4),  # FIXED
        false, :discrete)
    d_id = add_stochastic_vertex!(bn, vn_D, 
        (env, _) -> Normal(AbstractPPL.get(env, vn_B) + AbstractPPL.get(env, vn_C), 1.0), 
        true, :continuous)  # Observed
    
    # Add edges
    add_edge!(bn, vn_A, vn_B)
    add_edge!(bn, vn_A, vn_C)
    add_edge!(bn, vn_B, vn_D)
    add_edge!(bn, vn_C, vn_D)
    
    # Create evaluation environment
    bn = BayesianNetwork(
        bn.graph,
        bn.names,
        bn.names_to_ids,
        init_env,
        loop_vars_dict,
        bn.distributions,
        bn.deterministic_functions,
        bn.stochastic_ids,
        bn.deterministic_ids,
        bn.is_stochastic,
        bn.is_observed,
        bn.node_types,
        Dict{VarName, Int}(),
        0,
    )
    
    return bn
end
# Manual calculation for verification
function manual_logp()
    total = 0.0
    # Enumerate all possible states
    for a_val in [0, 1], b_val in [0, 1], c_val in [0, 1]
        # Prior probabilities
        p_a = a_val == 1 ? 0.4 : 0.6
        p_b_given_a = a_val == 1 ? (b_val == 1 ? 0.7 : 0.3) : (b_val == 1 ? 0.3 : 0.7)
        p_c_given_a = a_val == 1 ? (c_val == 1 ? 0.6 : 0.4) : (c_val == 1 ? 0.4 : 0.6)
        
        # Likelihood for D
        mu = b_val + c_val
        p_d = pdf(Normal(mu, 1.0), 1.5)
        
        # Joint probability
        joint_p = p_a * p_b_given_a * p_c_given_a * p_d
        total += joint_p
    end
    return log(total)
end

using AbstractPPL
using Graphs
using BenchmarkTools
using Test
using Printf
function create_tree_network(depth::Int)
    # Create initial network
    bn = BayesianNetwork{VarName}()

    # Define variables - a binary tree has 2^depth-1 nodes
    node_count = 2^depth - 1
    variables = [Symbol("z$i") for i in 1:node_count]
    push!(variables, :y)  # Observation variable

    # Initialize tracking - set all nodes to 0 initially
    all_vars, loop_vars = init_network_variables(variables)
    all_vars[:y] = 3.7  # Set observation

    # Add root node
    root_var = VarName(Symbol("z1"))
    add_stochastic_vertex!(bn, root_var, (_, _) -> Bernoulli(0.5), false, :discrete)

    # Add nodes level by level - FIXED PARENT-CHILD RELATIONSHIPS
    for level in 0:(depth-2)  # Corrected level indexing
        level_start = 2^level
        level_end = 2^(level+1) - 1
        
        for i in level_start:level_end
            # Calculate child indices
            left_child = 2*i
            right_child = 2*i + 1
            
            # Only add children if within node count
            if left_child <= node_count
                child_var = VarName(Symbol("z$left_child"))
                add_stochastic_vertex!(
                    bn,
                    child_var,
                    (env, _) -> begin
                        parent_val = AbstractPPL.get(env, VarName(Symbol("z$i")))
                        p = 0.3 + 0.4 * parent_val
                        return Bernoulli(p)
                    end,
                    false,
                    :discrete,
                )
                add_edge!(bn, VarName(Symbol("z$i")), child_var)
            end
            
            if right_child <= node_count
                child_var = VarName(Symbol("z$right_child"))
                add_stochastic_vertex!(
                    bn,
                    child_var,
                    (env, _) -> begin
                        parent_val = AbstractPPL.get(env, VarName(Symbol("z$i")))
                        p = 0.3 + 0.4 * parent_val
                        return Bernoulli(p)
                    end,
                    false,
                    :discrete,
                )
                add_edge!(bn, VarName(Symbol("z$i")), child_var)
            end
        end
    end

    # Add observable that depends on leaf nodes - FIXED LEAF NODE IDENTIFICATION
    y_var = VarName(:y)
    leaf_start = 2^(depth-1)  # First leaf at 2^(depth-1)
    leaf_end = 2^depth - 1    # Last leaf at 2^depth - 1

    add_stochastic_vertex!(
        bn,
        y_var,
        (env, _) -> begin
            # Observable depends on average of leaf values
            leaf_sum = 0.0
            count = 0
            for i in leaf_start:leaf_end
                leaf_var = VarName(Symbol("z$i"))
                leaf_val = AbstractPPL.get(env, leaf_var)
                leaf_sum += leaf_val
                count += 1
            end
            leaf_avg = leaf_sum / count
            mu = leaf_avg * 10.0
            return Normal(mu, 1.0)
        end,
        true,  # y is observed
        :continuous,
    )

    # Add dependency edges from all leaf nodes to y
    for i in leaf_start:leaf_end
        leaf_var = VarName(Symbol("z$i"))
        add_edge!(bn, leaf_var, y_var)
    end

    # Create evaluation environment
    eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

    # Create final network
    new_bn = BayesianNetwork(
        bn.graph,
        bn.names,
        bn.names_to_ids,
        eval_env,
        loop_vars,
        bn.distributions,
        bn.deterministic_functions,
        bn.stochastic_ids,
        bn.deterministic_ids,
        bn.is_stochastic,
        bn.is_observed,
        bn.node_types,
        Dict{VarName, Int}(),
        0,
    )

    return new_bn
end
# Helper functions
varname(sym::Symbol) = VarName(sym)

function benchmark_heuristics(bn, params)
    heuristics = [:dfs, :min_degree, :min_fill]
    results = []
    reference_logp = nothing
    
    # Function to capture memo size
    function run_with_memo_size(heuristic)
        sorted_nodes = topological_sort_with_heuristic(bn, heuristic)
        minimal_keys = _precompute_minimal_cache_keys(bn, sorted_nodes)
        memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
        
        # Create fresh environment
        env = deepcopy(bn.evaluation_env)
        
        # Run and capture memo size
        logp = _marginalize_recursive(
            bn, env, sorted_nodes, params, 1,
            bn.transformed_var_lengths, memo, :minimal_key, minimal_keys
        )
        return logp, length(memo)
    end
    
    for heuristic in heuristics
        println("Running $heuristic heuristic...")
        
        # Warmup
        _, _ = evaluate_with_marginalization(
            bn, params; caching_strategy=:minimal_key, order_heuristic=heuristic
        )
        
        # Benchmark time and get logp/memo_size
        t = @elapsed begin
            logp, memo_size = run_with_memo_size(heuristic)
        end
        
        # Set reference from first heuristic
        if reference_logp === nothing
            reference_logp = logp
            println("Reference logp: $reference_logp")
        else
            # Use more robust comparison
            if !isapprox(reference_logp, logp, rtol=1e-8, atol=1e-8)
                @error "Log probability mismatch: $reference_logp vs $logp (heuristic: $heuristic)"
            end
            @test isapprox(reference_logp, logp, rtol=1e-8, atol=1e-8)
        end
        
        push!(results, (heuristic, t, memo_size))
    end
    
    return results
end

# Print results table
function print_heuristic_results(network_type, size_info, results)
    # Header
    println("\n=== $network_type Network ($size_info) ===")
    println("Heuristic    | Time (s)     | Memo Size | Speedup (vs DFS)")
    println("------------|--------------|-----------|-----------------")
    
    # Find DFS time for speedup calculation
    dfs_time = nothing
    for (heuristic, time, memo_size) in results
        if heuristic == :dfs
            dfs_time = time
            break
        end
    end
    
    # Print rows
    for (heuristic, time, memo_size) in results
        speedup = dfs_time / time
        @printf("%-12s| %-12.4e | %-9d | %.2fx\n", 
                heuristic, time, memo_size, speedup)
    end
end



# Main benchmarking function
function benchmark_heuristics_all()
    # Chain networks
    chain_results = []
    for n in [5, 7, 9, 11,13, 15, 17, 19, 20]  # Start with smaller chains for debugging
        bn = create_chain_network(n)
        params = Float64[]
        println("\nBenchmarking chain network with $n nodes")
        
        results = benchmark_heuristics(bn, params)
        print_heuristic_results("Chain", "$n nodes", results)
        push!(chain_results, (n, results))
    end
    
    # Tree networks - start with smaller sizes
    tree_results = []
    for depth in [2, 3,4]  # Start with smaller trees for debugging
        n_nodes = 2^depth - 1
        bn = create_tree_network(depth)
        params = Float64[]
        println("\nBenchmarking tree network with depth $depth ($n_nodes nodes)")
        
        results = benchmark_heuristics(bn, params)
        print_heuristic_results("Tree", "Depth $depth ($n_nodes nodes)", results)
        push!(tree_results, (depth, results))
    end
    
    # Return results for further analysis
    return (chain_results, tree_results)
end

# Helper function to get memo size
function run_with_memo_size(bn, params, heuristic)
    memo = Dict{Tuple{Int,Int,UInt64}, Float64}()
    minimal_keys = _precompute_minimal_cache_keys(bn)
    sorted_nodes = topological_sort_with_heuristic(bn, heuristic)
    env = deepcopy(bn.evaluation_env)
    
    logp = _marginalize_recursive(
        bn, env, sorted_nodes, params, 1,
        bn.transformed_var_lengths, memo, :minimal_key, minimal_keys
    )
    return logp, length(memo)
end

# Run the benchmarks
benchmark_heuristics_all()


# Grid networks
grid_sizes = [(3,3), (3,4),(4,3), (4,4), (4,5)]
for (w,h) in grid_sizes
    bn = create_grid_network(w, h)
    params = Float64[]
    println("\nBenchmarking grid network $w x $h ($(w*h) nodes)")
    
    results = benchmark_heuristics(bn, params)
    print_heuristic_results("Grid", "$w x $h ($(w*h) nodes)", results)
end

function create_enhanced_grid_network(width::Int, height::Int)
    # Create initial network
    bn = BayesianNetwork{VarName}()
    
    # Define variables with proper naming convention
    variables = [Symbol("z$(i)_$(j)") for i in 1:height for j in 1:width]
    push!(variables, :y)  # Observation variable
    
    # Initialize tracking - create arrays of zeros for all variables
    init_values = zeros(length(variables))
    all_vars, loop_vars = init_network_variables(variables, init_values)
    all_vars = BangBang.setindex!!(all_vars, 3.7, :y)  # Set observation value
    
    # Create a matrix to track VarNames for easy access
    grid = Matrix{VarName}(undef, height, width)
    for i in 1:height, j in 1:width
        sym = Symbol("z$(i)_$(j)")
        grid[i, j] = VarName(sym)
    end
    
    # Add nodes with enhanced connectivity
    for i in 1:height, j in 1:width
        var = grid[i, j]
        
        # Collect all valid neighbor positions
        neighbors = VarName[]
        for di in -1:1, dj in -1:1
            (di == 0 && dj == 0) && continue  # Skip self
            ni, nj = i + di, j + dj
            if 1 <= ni <= height && 1 <= nj <= width
                # Only connect to neighbors that come before in row-major order
                if (ni < i) || (ni == i && nj < j)
                    push!(neighbors, grid[ni, nj])
                end
            end
        end
        
        # Add node with appropriate dependencies
        if isempty(neighbors)
            # Top-left corner node has no dependencies
            add_stochastic_vertex!(
                bn, var, (_, _) -> Bernoulli(0.5), false, :discrete
            )
        else
            # Fixed syntax: use end instead of } for function block
            add_stochastic_vertex!(
                bn,
                var,
                (env, _) -> begin
                    neighbor_sum = 0.0
                    for neighbor in neighbors
                        neighbor_sum += AbstractPPL.get(env, neighbor)
                    end
                    p = min(0.3 + 0.1 * neighbor_sum, 0.95)
                    return Bernoulli(p)
                end,  # Fixed: use 'end' to close function block
                false,
                :discrete,
            )
            
            # Add dependency edges to all neighbors
            for neighbor in neighbors
                add_edge!(bn, neighbor, var)
            end
        end
    end
    
    # Add observable that depends on ALL grid nodes
    y_var = VarName(:y)
    add_stochastic_vertex!(
        bn,
        y_var,
        (env, _) -> begin
            total = 0.0
            for i in 1:height, j in 1:width
                total += AbstractPPL.get(env, grid[i, j])
            end
            return Normal(total, 1.0)
        end,  # Fixed: use 'end' to close function block
        true,
        :continuous,
    )
    
    # Add dependency edges from all grid nodes to y
    for i in 1:height, j in 1:width
        add_edge!(bn, grid[i, j], y_var)
    end
    
    # Create evaluation environment
    eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))
    
    # Create final network
    new_bn = BayesianNetwork(
        bn.graph,
        bn.names,
        bn.names_to_ids,
        eval_env,
        loop_vars,
        bn.distributions,
        bn.deterministic_functions,
        bn.stochastic_ids,
        bn.deterministic_ids,
        bn.is_stochastic,
        bn.is_observed,
        bn.node_types,
        Dict{VarName, Int}(),
        0,
    )
    
    return new_bn
end


# Benchmark different grid sizes
grid_sizes = [(3,3), (4,4)]
for (w, h) in grid_sizes
    bn = create_enhanced_grid_network(w, h)
    params = Float64[]
    println("\nBenchmarking enhanced grid $w x $h ($(w*h) nodes)")
    
    results = benchmark_heuristics(bn, params)
    print_heuristic_results("Enhanced Grid", "$w x $h ($(w*h) nodes)", results)
end

function create_diamond_network(layers::Int)
    # Create initial network
    bn = BayesianNetwork{VarName}()
    
    # Calculate total nodes
    total_nodes = layers * (layers + 1) ÷ 2
    variables = [Symbol("n$(i)_$(j)") for i in 1:layers for j in 1:i]
    push!(variables, :y)  # Observation variable
    
    # Initialize tracking
    all_vars, loop_vars = init_network_variables(variables)
    all_vars[:y] = 3.7  # Set observation value
    
    # Create nodes with increasing connectivity
    node_dict = Dict{Tuple{Int,Int}, VarName}()
    for i in 1:layers, j in 1:i
        node_sym = Symbol("n$(i)_$(j)")
        vn = VarName(node_sym)
        node_dict[(i, j)] = vn
        
        # Add node with dependencies
        if i == 1
            # Root node
            add_stochastic_vertex!(
                bn, vn, (_, _) -> Bernoulli(0.5), false, :discrete
            )
        else
            # Collect parents from previous layer
            parents = VarName[]
            if j > 1  # Left parent
                push!(parents, node_dict[(i-1, j-1)])
            end
            if j < i  # Right parent (only if not last in layer)
                push!(parents, node_dict[(i-1, j)])
            end
            
            add_stochastic_vertex!(
                bn,
                vn,
                (env, _) -> begin
                    parent_sum = 0.0
                    for parent in parents
                        parent_sum += AbstractPPL.get(env, parent)
                    end
                    p = min(0.3 + 0.2 * parent_sum, 0.95)
                    return Bernoulli(p)
                end,
                false,
                :discrete,
            )
            
            # Add dependency edges
            for parent in parents
                add_edge!(bn, parent, vn)
            end
        end
    end
    
    # Add observation node that depends on all nodes
    y_var = VarName(:y)
    add_stochastic_vertex!(
        bn,
        y_var,
        (env, _) -> begin
            total = 0.0
            for i in 1:layers, j in 1:i
                total += AbstractPPL.get(env, node_dict[(i, j)])
            end
            return Normal(total, 1.0)
        end,
        true,
        :continuous,
    )
    
    # Add dependency edges from all nodes to y
    for vn in values(node_dict)
        add_edge!(bn, vn, y_var)
    end
    
    # Create evaluation environment
    eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))
    
    # Create final network
    new_bn = BayesianNetwork(
        bn.graph,
        bn.names,
        bn.names_to_ids,
        eval_env,
        loop_vars,
        bn.distributions,
        bn.deterministic_functions,
        bn.stochastic_ids,
        bn.deterministic_ids,
        bn.is_stochastic,
        bn.is_observed,
        bn.node_types,
        Dict{VarName, Int}(),
        0,
    )
    
    return new_bn
end

# Benchmark diamond networks
diamond_sizes = [4, 5, 6]  # Layers: 4(10 nodes), 5(15 nodes), 6(21 nodes)
for layers in diamond_sizes
    bn = create_diamond_network(layers)
    params = Float64[]
    println("\nBenchmarking diamond network with $layers layers ($(layers*(layers+1)÷2) nodes)")
    
    results = benchmark_heuristics(bn, params)
    print_heuristic_results("Diamond", "$layers layers ($(layers*(layers+1)÷2) nodes)", results)
end

function create_dense_hmm_network(n_states::Int, seq_length::Int)
    bn = BayesianNetwork{VarName}()

    # Hidden states and observation variables
    z_vars = [VarName(Symbol("z$t")) for t in 1:seq_length]
    x_vars = [VarName(Symbol("x$t")) for t in 1:seq_length]

    # Initialize tracking variables
    all_vars = Dict{Symbol, Any}()
    loop_vars = Dict{VarName, NamedTuple}()

    # Initialize with default values
    for t in 1:seq_length
        all_vars[Symbol("z$t")] = 1      # Default to first state
        all_vars[Symbol("x$t")] = 0.0    # Observation placeholder
        loop_vars[z_vars[t]] = (;)
        loop_vars[x_vars[t]] = (;)
    end

    # Add first hidden state node
    add_stochastic_vertex!(bn, z_vars[1],
        (_, _) -> Categorical(ones(n_states) / n_states), false, :discrete)

    # Add second hidden state node (depends on first)
    if seq_length >= 2
        add_stochastic_vertex!(bn, z_vars[2],
            (env, _) -> begin
                prev_state = AbstractPPL.get(env, z_vars[1])
                # Simple transition model based on previous state
                probs = ones(n_states) / n_states
                return Categorical(probs)
            end,
            false, :discrete)
        add_edge!(bn, z_vars[1], z_vars[2])
    end

    # Add subsequent hidden state nodes with dependencies on previous two states (skip connections)
    for t in 3:seq_length
        add_stochastic_vertex!(bn, z_vars[t],
            (env, _) -> begin
                prev1_state = AbstractPPL.get(env, z_vars[t-1])
                prev2_state = AbstractPPL.get(env, z_vars[t-2])
                # For simplicity, uniform transition regardless of previous states
                probs = ones(n_states) / n_states
                return Categorical(probs)
            end,
            false, :discrete)
        add_edge!(bn, z_vars[t-1], z_vars[t])
        add_edge!(bn, z_vars[t-2], z_vars[t])  # Skip connection to t-2
    end

    # Add observation nodes
    for t in 1:seq_length
        add_stochastic_vertex!(bn, x_vars[t],
            (env, _) -> begin
                state = AbstractPPL.get(env, z_vars[t])
                return Normal(Float64(state), 1.0)
            end,
            true, :continuous)
        add_edge!(bn, z_vars[t], x_vars[t])
    end

    # Create evaluation environment
    eval_env = NamedTuple{Tuple(keys(all_vars))}(values(all_vars))

    # Return final network
    return BayesianNetwork(
        bn.graph,
        bn.names,
        bn.names_to_ids,
        eval_env,
        loop_vars,
        bn.distributions,
        bn.deterministic_functions,
        bn.stochastic_ids,
        bn.deterministic_ids,
        bn.is_stochastic,
        bn.is_observed,
        bn.node_types,
        Dict{VarName, Int}(),
        0,
    )
end

function benchmark_heuristics(bn, params)
    heuristics = [:dfs, :min_degree, :min_fill]
    results = []
    reference_logp = nothing
    
    # Baseline: No memoization time for speedup comparison
    println("Running baseline (no memoization)...")
    baseline_time = @elapsed begin
        _, no_memo_logp = marginalize_without_memo(deepcopy(bn), params)
    end
    reference_logp = no_memo_logp
    println("Baseline time: $baseline_time s, Reference logp: $reference_logp")
    
    # Function to capture memo size and logp with specific heuristic
    function run_with_memo_size(heuristic)
        # Get elimination order for this heuristic
        sorted_nodes = topological_sort_with_heuristic(bn, heuristic)
        # Compute minimal keys specifically for this elimination order
        minimal_keys = _precompute_minimal_cache_keys(bn, sorted_nodes)
        memo = Dict{Tuple{Int, Int, UInt64}, Float64}()
        
        # Create fresh environment
        env = deepcopy(bn.evaluation_env)
        
        # Run and capture memo size
        logp = _marginalize_recursive(
            bn, env, sorted_nodes, params, 1,
            bn.transformed_var_lengths, memo, :minimal_key, minimal_keys
        )
        return logp, length(memo)
    end
    
    for heuristic in heuristics
        println("Running $heuristic heuristic...")
        
        # Warmup
        evaluate_with_marginalization(
            bn, params; caching_strategy=:minimal_key, order_heuristic=heuristic
        )
        
        # Benchmark time and get logp/memo_size
        t = @elapsed begin
            logp, memo_size = run_with_memo_size(heuristic)
        end
        
        # Verify correctness against reference
        if !isapprox(reference_logp, logp, rtol=1e-8, atol=1e-8)
            @error "Log probability mismatch: $reference_logp vs $logp (heuristic: $heuristic)"
        end
        @test isapprox(reference_logp, logp, rtol=1e-8, atol=1e-8)
        
        # Calculate speedup relative to baseline
        speedup = baseline_time / t
        
        push!(results, (heuristic=heuristic, time=t, speedup=speedup, memo_size=memo_size))
    end
    
    return results, baseline_time
end

# Helper function to display results
function display_heuristic_results(results, baseline_time)
    println("\n=== Heuristic Performance Comparison ===")
    println("Baseline (No Memo) Time: $(round(baseline_time, digits=3))s")
    println("Heuristic     | Time (s) | Speedup | Memo Size")
    println("--------------|----------|---------|-----------")
    
    for r in results
        println(rpad(string(r.heuristic), 13), " | ",
            @sprintf("%8.3f", r.time), " | ",
            @sprintf("%7.2fx", r.speedup), " | ",
            @sprintf("%9d", r.memo_size))
    end
end

# Create a dense HMM network (e.g., 2 states, sequence length 6)
bn = create_dense_hmm_network(2, 6)
params = Float64[]

# Run benchmark with different heuristics
results, baseline_time = benchmark_heuristics(bn, params)

# Display results
display_heuristic_results(results, baseline_time)


function test_dense_hmm_variations()
    # Test different configurations
    state_configs = [2, 3]  # Number of states
    seq_configs = [4, 6, 8, 10, 12, 14]  # Sequence lengths
    params = Float64[]
    
    all_results = []
    
    for n_states in state_configs
        for seq_length in seq_configs
            println("\n=== Testing Dense HMM: $n_states states, length $seq_length ===")
            bn = create_dense_hmm_network(n_states, seq_length)
            
            # Run benchmark with different heuristics
            results, baseline_time = benchmark_heuristics(bn, params)
            
            # Store results with configuration
            push!(all_results, (
                n_states=n_states,
                seq_length=seq_length,
                baseline_time=baseline_time,
                heuristic_results=results
            ))
            
            # Display results for this configuration
            display_heuristic_results(results, baseline_time)
        end
    end
    
    # Summarize all results
    println("\n=== Summary Across All Configurations ===")
    println("States | Length | Heuristic     | Time (s) | Speedup | Memo Size")
    println("-------|--------|--------------|----------|---------|-----------")
    
    for res in all_results
        for hr in res.heuristic_results
            println(
                @sprintf("%6d", res.n_states), " | ",
                @sprintf("%6d", res.seq_length), " | ",
                rpad(string(hr.heuristic), 13), " | ",
                @sprintf("%8.3f", hr.time), " | ",
                @sprintf("%7.2fx", hr.speedup), " | ",
                @sprintf("%9d", hr.memo_size)
            )
        end
    end
    
    return all_results
end

# Run the test
all_results = test_dense_hmm_variations()
