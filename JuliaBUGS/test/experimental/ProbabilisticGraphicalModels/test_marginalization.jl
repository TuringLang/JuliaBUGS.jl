using Test
using Distributions
using JuliaBUGS
using JuliaBUGS: @bugs, compile, VarName
using JuliaBUGS.ProbabilisticGraphicalModels:
    BayesianNetwork,
    translate_BUGSGraph_to_BayesianNetwork,
    evaluate_with_marginalization,
    _marginalize_recursive,
    _precompute_minimal_cache_keys
using BangBang
using AbstractPPL
using LogExpFunctions
using LogDensityProblems

# Register distributions for use in @bugs
JuliaBUGS.@bugs_primitive Bernoulli Uniform Normal

# Helper functions for marginalization tests
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
    _, margin_logp = evaluate_with_marginalization(
        bn, params; caching_strategy=:minimal_key
    )

    # Test against expected result
    @test margin_logp ≈ expected_logp rtol = rtol

    return margin_logp
end

@testset "Marginalization for Discrete Variables" begin
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
                bn, Dict(vars["z"] => :discrete), Dict(vars["y"] => y_value), expected_logp
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
                compiled_model.g, compiled_model.evaluation_env, compiled_model
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
                compiled_model.g, compiled_model.evaluation_env
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
            sort!(z_vars; by=x -> Base.parse(Int, string(x)[2:end]))
            sort!(y_vars; by=x -> Base.parse(Int, string(x)[2:end]))

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
                bn, params; caching_strategy=:minimal_key
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
                    p *= trans_prob(states[i - 1], states[i])
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
            @test isapprox(margin_logp, manual_logp, rtol=1E-6)
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
            compiled_model.g, compiled_model.evaluation_env
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
        _, margin_logp = evaluate_with_marginalization(
            bn, params; caching_strategy=:minimal_key
        )

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

        @test isapprox(margin_logp, expected_logp, rtol=1E-6)
    end
end
