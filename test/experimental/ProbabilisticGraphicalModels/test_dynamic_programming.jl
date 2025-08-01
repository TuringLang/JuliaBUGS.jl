using Test
using Distributions
using Graphs
using JuliaBUGS.ProbabilisticGraphicalModels:
    BayesianNetwork,
    add_stochastic_vertex!,
    add_deterministic_vertex!,
    add_edge!,
    evaluate_with_marginalization,
    _marginalize_recursive,
    _precompute_minimal_cache_keys
using JuliaBUGS: VarName, @varname
using BangBang
using AbstractPPL

# Helper functions for baseline comparisons
function marginalize_with_full_env_baseline(bn, params)
    # Use a simple DFS ordering, as the full environment key does not depend on ordering.
    sorted_node_ids = topological_sort_by_dfs(bn.graph)
    env = deepcopy(bn.evaluation_env)

    # 1. Initialize an empty memoization cache
    memo = Dict{Tuple{Int,Int,UInt64},Any}()

    # 2. Call the main recursive function with the :full_env caching strategy
    logp = JuliaBUGS.ProbabilisticGraphicalModels._marginalize_recursive(
        bn,
        env,
        sorted_node_ids,
        params,
        1,
        bn.transformed_var_lengths,
        memo,         # Pass the cache
        :full_env,     # Specify the caching strategy
        Dict(),  # Pass an empty minimal_keys dictionary
    )

    # Return the log probability and the final memoization cache for analysis
    return env, logp
end

function marginalize_with_memo(bn, params)
    sorted_node_ids = topological_sort_by_dfs(bn.graph)
    env = deepcopy(bn.evaluation_env)
    memo = Dict{Tuple{Int,Int,UInt64},Any}() # there is a difference between pass this and not passing this
    minimal_keys = JuliaBUGS.ProbabilisticGraphicalModels._precompute_minimal_cache_keys(bn)

    # Use the enhanced function with memo
    logp = JuliaBUGS.ProbabilisticGraphicalModels._marginalize_recursive(
        bn,
        env,
        sorted_node_ids,
        params,
        1,
        bn.transformed_var_lengths,
        memo,
        :minimal_key,
        minimal_keys,
    )
    return env, logp, length(memo)
end

@testset "Dynamic Programming in Marginalization" begin

    # Helper function to create graph without using compiler
    function create_chain_bayesian_network(n_chain)
        # Create initial network
        bn = BayesianNetwork{VarName}()

        # Initialize loop_vars to track as we build
        loop_vars = Dict{VarName,NamedTuple}()

        # Track variables to create full environment later
        all_vars = Dict{Symbol,Any}()

        # Add first node
        first_var = VarName{Symbol("z[1]")}()
        add_stochastic_vertex!(bn, first_var, (_, _) -> Bernoulli(0.5), false, :discrete)
        loop_vars[first_var] = (;)  # Empty named tuple
        all_vars[Symbol("z[1]")] = 0  # Initialize with value 0

        # Add subsequent nodes with dependencies
        for i in 2:n_chain
            var = VarName{Symbol("z[$i]")}()
            prev_var = VarName{Symbol("z[$(i-1)]")}()

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
        y_var = VarName{:y}()
        last_var = VarName{Symbol("z[$n_chain]")}()

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
            Dict{VarName,Int}(),  # empty transformed_var_lengths
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
        t1 = @elapsed _, logp1 = marginalize_with_full_env_baseline(bn, params)
        t2 = @elapsed _, logp2, memo_size = marginalize_with_memo(bn, params)

        # Verify results match
        @test isapprox(logp1, logp2, rtol=1e-10)

        @test memo_size == 11
    end

    @testset "Correctness with Tricky Dependency Graph" begin
        # Create a complex graph manually to ensure it's acyclic
        # Start with an initial network
        original_bn = BayesianNetwork{VarName}()

        # Initialize loop_vars to track as we build
        loop_vars = Dict{VarName,NamedTuple}()

        # Track all variables to create full environment
        all_vars = Dict{Symbol,Any}()

        # Root nodes
        x_var = VarName{:x}()
        y_var = VarName{:y}()

        # Add them to the network
        add_stochastic_vertex!(
            original_bn, x_var, (_, _) -> Bernoulli(0.3), false, :discrete
        )
        add_stochastic_vertex!(
            original_bn, y_var, (_, _) -> Bernoulli(0.7), false, :discrete
        )
        loop_vars[x_var] = (;)
        loop_vars[y_var] = (;)
        all_vars[:x] = 0  # Initialize with value 0
        all_vars[:y] = 0  # Initialize with value 0

        # Variable with multiple parents
        z_var = VarName{:z}()
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
        w_var = VarName{:w}()
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
        obs1_var = VarName{:obs1}()
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

        obs2_var = VarName{:obs2}()
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
            Dict{VarName,Int}(),
            0,
        )

        # Run with original function
        env1, logp1 = marginalize_with_full_env_baseline(bn, Float64[])

        # Run with memoized function
        env2, logp2, memo_size = marginalize_with_memo(bn, Float64[])

        # Verify results match
        @test isapprox(logp1, logp2, rtol=1e-10)
        @test memo_size == 35

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
            joint_prob = p_x1 * p_y0 * p_z1_given_x1_y0 * p_w1_given_z1 * p_obs1 * p_obs2

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
    function init_network_variables(variables, init_values=nothing)
        all_vars = Dict{Symbol,Any}()
        loop_vars = Dict{VarName,NamedTuple}()

        for (i, var) in enumerate(variables)
            var_name = typeof(var) == Symbol ? var : Symbol(var)
            var_value = init_values === nothing ? 0 : init_values[i]
            all_vars[var_name] = var_value
            loop_vars[VarName{var_name}()] = (;)
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
        first_var = VarName{Symbol("z1")}()
        add_stochastic_vertex!(bn, first_var, (_, _) -> Bernoulli(0.5), false, :discrete)

        # Add subsequent nodes with dependencies
        for i in 2:length
            var = VarName{Symbol("z$i")}()
            prev_var = VarName{Symbol("z$(i-1)")}()

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
        y_var = VarName{:y}()
        last_var = VarName{Symbol("z$length")}()

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
            Dict{VarName,Int}(),
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
        root_var = VarName{Symbol("z1")}()
        add_stochastic_vertex!(bn, root_var, (_, _) -> Bernoulli(0.5), false, :discrete)

        # Add nodes level by level
        for level in 1:(depth - 1)
            start_idx = 2^level
            end_idx = 2^(level + 1) - 1
            parent_start = 2^(level - 1)

            for i in start_idx:end_idx
                var = VarName{Symbol("z$i")}()
                parent_idx = parent_start + div(i - start_idx, 2)
                parent_var = VarName{Symbol("z$parent_idx")}()

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
        y_var = VarName{:y}()
        leaf_start = 2^(depth - 1)
        leaf_end = 2^depth - 1

        add_stochastic_vertex!(
            bn,
            y_var,
            (env, _) -> begin
                # Observable depends on average of leaf values
                leaf_sum = 0.0
                for i in leaf_start:leaf_end
                    leaf_var = VarName{Symbol("z$i")}()
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
            leaf_var = VarName{Symbol("z$i")}()
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
            Dict{VarName,Int}(),
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
                var = VarName{Symbol("z$(i)_$(j)")}()

                # Determine dependencies
                has_left = j > 1
                has_above = i > 1

                # Add node with appropriate dependencies
                if !has_left && !has_above
                    # Top-left node has no dependencies
                    add_stochastic_vertex!(
                        bn, var, (_, _) -> Bernoulli(0.5), false, :discrete
                    )
                else
                    # Node depends on nodes above and/or to the left
                    add_stochastic_vertex!(
                        bn,
                        var,
                        (env, _) -> begin
                            p_base = 0.3  # Base probability

                            if has_left
                                left_var = VarName{Symbol("z$(i)_$(j-1)")}()
                                left_val = AbstractPPL.get(env, left_var)
                                p_base += 0.2 * left_val
                            end

                            if has_above
                                above_var = VarName{Symbol("z$(i-1)_$(j)")}()
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
                        left_var = VarName{Symbol("z$(i)_$(j-1)")}()
                        add_edge!(bn, left_var, var)
                    end

                    if has_above
                        above_var = VarName{Symbol("z$(i-1)_$(j)")}()
                        add_edge!(bn, above_var, var)
                    end
                end
            end
        end

        # Add observable that depends on bottom-right nodes
        y_var = VarName{:y}()

        add_stochastic_vertex!(
            bn,
            y_var,
            (env, _) -> begin
                # Observable depends on the value of the bottom-right node
                bottom_right_var = VarName{Symbol("z$(height)_$(width)")}()
                bottom_right_val = AbstractPPL.get(env, bottom_right_var)
                mu = bottom_right_val * 5.0
                return Normal(mu, 1.0)
            end,
            true,
            :continuous,
        )

        # Add dependency edge from bottom-right node
        bottom_right_var = VarName{Symbol("z$(height)_$(width)")}()
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
            Dict{VarName,Int}(),
            0,
        )

        return new_bn
    end

    @testset "Chain Network Scaling Tests" begin

        # Expected memoization sizes based on your provided log output.
        # The test will verify that the DP implementation produces exactly these cache sizes.
        expected_memo_sizes = Dict(
            2 => 5, 3 => 7, 4 => 9, 5 => 11, 6 => 13, 7 => 15, 8 => 17, 9 => 19, 10 => 21
        )

        # Define the chain lengths to be tested.
        chain_lengths_to_test = [2, 3, 4, 5, 6, 7, 8, 9, 10]

        # Loop through each configuration and run the tests.
        for len in chain_lengths_to_test
            @testset "Chain Length: $len" begin
                # --- Setup ---
                bn = create_chain_network(len)
                params = Float64[]

                # --- Execution ---
                # Run both versions of the algorithm to get their results.
                _, logp_standard = marginalize_with_full_env_baseline(bn, params)
                _, logp_dp, memo_size = marginalize_with_memo(bn, params)

                # --- Assertions ---
                # 1. Test for correctness: The log probabilities should be nearly identical.
                @test isapprox(logp_standard, logp_dp, rtol=1e-10)

                # 2. Test for memoization size: The cache size must match the expected value.
                @test memo_size == expected_memo_sizes[len]
            end
        end
    end

    @testset "Tree Network Scaling Tests" begin

        # Expected memoization sizes for each tree depth, based on your log output.
        expected_tree_memo_sizes = Dict(2 => 11, 3 => 63)

        # Define the tree depths to be tested.
        tree_depths_to_test = [2, 3]

        for depth in tree_depths_to_test
            @testset "Tree Depth: $depth" begin
                # --- Setup ---
                bn = create_tree_network(depth)
                params = Float64[]

                # --- Execution ---
                _, logp_standard = marginalize_with_full_env_baseline(bn, params)
                _, logp_dp, memo_size = marginalize_with_memo(bn, params)

                # --- Assertions ---
                # 1. Test correctness: The log probabilities must match.
                @test isapprox(logp_standard, logp_dp, rtol=1e-10)

                # 2. Test memoization size: The cache size must match the expected value.
                @test memo_size == expected_tree_memo_sizes[depth]
            end
        end
    end

    @testset "Grid Network Scaling Tests" begin

        # Expected memoization sizes for each grid size, based on your log output.
        expected_grid_memo_sizes = Dict((2, 2) => 13, (2, 3) => 21, (3, 3) => 53)

        # Define the grid sizes to be tested.
        grid_sizes_to_test = [(2, 2), (2, 3), (3, 3)]

        for (width, height) in grid_sizes_to_test
            @testset "Grid Size: $(width)x$(height)" begin
                # --- Setup ---
                bn = create_grid_network(width, height)
                params = Float64[]

                # --- Execution ---
                _, logp_standard = marginalize_with_full_env_baseline(bn, params)
                _, logp_dp, memo_size = marginalize_with_memo(bn, params)

                # --- Assertions ---
                # 1. Test correctness: The log probabilities must match.
                @test isapprox(logp_standard, logp_dp, rtol=1e-10)

                # 2. Test memoization size: The cache size must match the expected value.
                @test memo_size == expected_grid_memo_sizes[(width, height)]
            end
        end
    end
end
