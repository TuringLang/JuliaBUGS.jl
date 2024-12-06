using Distributions
using Printf

# Add logistic function definition
logistic(x) = 1 / (1 + exp(-x))

# New BayesNet structure
struct BayesNet{T}
    nodes::Dict{Symbol,T}  # Distribution or function returning distribution
    edges::Dict{Symbol,Vector{Symbol}}  # Child -> Parents
end

# Helper to create a BayesNet
function create_bayes_net(nodes::Dict{Symbol,Any}, edges::Dict{Symbol,Vector{Symbol}})
    return BayesNet(nodes, edges)
end
# Helper to create an n-node sequential network
function create_sequential_net_n(nodes::Vector{Any})
    n = length(nodes)
    node_dict = Dict{Symbol,Any}()
    edge_dict = Dict{Symbol,Vector{Symbol}}()

    # Create nodes X1 through Xn
    for i in 1:n
        node_symbol = Symbol("X$i")
        node_dict[node_symbol] = nodes[i]

        # Set edges (each node depends on previous node)
        if i == 1
            edge_dict[node_symbol] = Symbol[]  # X1 has no parents
        else
            edge_dict[node_symbol] = [Symbol("X$(i-1)")]  # Xi depends on X(i-1)
        end
    end

    return BayesNet(node_dict, edge_dict)
end

# Updated log_posterior function for multiple discrete marginalization
function create_log_posterior(
    net::BayesNet{T}, observations::Dict{Symbol,Float64}
) where {T}
    function find_discrete_nodes_to_marginalize(known_values::Dict{Symbol,Float64})
        nodes_to_marginalize = Symbol[]
        nodes_processed = Set{Symbol}()

        # Keep processing until no new nodes are added
        while true
            nodes_added = false

            for (node, dist) in net.nodes
                # Skip if we've already processed this node or if it's observed
                if node in nodes_processed || haskey(known_values, node)
                    continue
                end

                parents = get(net.edges, node, Symbol[])
                # Check if all parents are either known or will be marginalized
                if all(p -> haskey(known_values, p) || p in nodes_to_marginalize, parents)
                    # Get parent values that are known
                    parent_values = [
                        known_values[p] for p in parents if haskey(known_values, p)
                    ]

                    # Handle the case where dist is a function or a distribution
                    node_dist = if isempty(parents)
                        dist  # Direct distribution
                    else
                        # Create dummy values for marginalized parents
                        dummy_values = zeros(length(parents))
                        dist(dummy_values...)
                    end

                    if node_dist isa DiscreteDistribution
                        push!(nodes_to_marginalize, node)
                        nodes_added = true
                    end
                end
                push!(nodes_processed, node)
            end

            # If no new nodes were added, we're done
            if !nodes_added
                break
            end
        end

        # Sort nodes in topological order
        all_nodes = collect(keys(net.nodes))
        sort!(nodes_to_marginalize; by=n -> findfirst(==(n), all_nodes))

        println("Found nodes to marginalize: ", nodes_to_marginalize)  # Debug print
        return nodes_to_marginalize
    end

    function marginalize_recursive(
        nodes_to_marginalize::Vector{Symbol},
        current_values::Dict{Symbol,Float64},
        depth::Int=0,
    )  # Add depth parameter for indentation
        indent = "  "^depth  # Create indentation based on recursion depth

        println("$(indent)Entering marginalize_recursive:")
        println("$(indent)Nodes to marginalize: ", nodes_to_marginalize)
        println("$(indent)Current values: ", current_values)

        if isempty(nodes_to_marginalize)
            # Base case: compute probability of observations and prior
            prob = 1.0

            # Add prior probability for X1
            if haskey(current_values, :X1)
                prob *= pdf(net.nodes[:X1], current_values[:X1])
                println(
                    "$(indent)Computing prior P(X1=",
                    current_values[:X1],
                    ") = ",
                    pdf(net.nodes[:X1], current_values[:X1]),
                )
            end

            # Add probabilities for observations
            for (obs_node, obs_val) in observations
                parents = get(net.edges, obs_node, Symbol[])
                if !isempty(parents) && all(p -> haskey(current_values, p), parents)
                    parent_values = [current_values[p] for p in parents]
                    node_dist = net.nodes[obs_node](parent_values...)
                    prob *= pdf(node_dist, obs_val)
                    println(
                        "$(indent)Computing P(",
                        obs_node,
                        "=",
                        obs_val,
                        "|parents) = ",
                        pdf(node_dist, obs_val),
                    )
                end
            end
            println("$(indent)Base case returning prob = ", prob)
            return prob
        else
            # Recursive case: marginalize over current node
            current_node = nodes_to_marginalize[1]
            remaining_nodes = nodes_to_marginalize[2:end]

            println("$(indent)Processing node: ", current_node)

            # Get parent values and distribution for current node
            parents = get(net.edges, current_node, Symbol[])
            if !all(p -> haskey(current_values, p), parents)
                println("$(indent)Missing parent values for ", current_node, ", skipping")
                return 0.0
            end

            parent_values = [current_values[p] for p in parents]
            node_dist = if isempty(parents)
                net.nodes[current_node]
            else
                net.nodes[current_node](parent_values...)
            end

            println(
                "$(indent)Node distribution for ", current_node, " with parents ", parents
            )

            # Sum over all possible values of current node
            likelihood = 0.0
            for val in support(node_dist)
                new_values = copy(current_values)
                new_values[current_node] = val

                # Compute probability of current value
                p_val = pdf(node_dist, val)
                println("$(indent)Trying ", current_node, "=", val, " with P=", p_val)

                # Recursively compute probability of remaining nodes
                child_prob = marginalize_recursive(remaining_nodes, new_values, depth + 1)

                # Accumulate probability
                contribution = p_val * child_prob
                likelihood += contribution
                println(
                    "$(indent)Contribution from ",
                    current_node,
                    "=",
                    val,
                    ": ",
                    p_val,
                    " * ",
                    child_prob,
                    " = ",
                    contribution,
                )
            end

            println("$(indent)Total likelihood for this branch: ", likelihood)
            return likelihood
        end
    end

    function log_posterior(values::Dict{Symbol,Float64})
        known_values = merge(values, observations)
        nodes_to_marginalize = find_discrete_nodes_to_marginalize(known_values)

        println("\nStarting log_posterior computation:")
        println("Known values: ", known_values)
        println("Nodes to marginalize: ", nodes_to_marginalize)

        if isempty(nodes_to_marginalize)
            println("No marginalization needed")
            # Direct computation when no marginalization needed
            log_p = logpdf(net.nodes[:X1], known_values[:X1])
            println("Prior log probability: ", log_p)
            for (node, obs_val) in observations
                parents = get(net.edges, node, Symbol[])
                if !isempty(parents)
                    parent_values = [known_values[p] for p in parents]
                    node_dist = net.nodes[node](parent_values...)
                    log_p += logpdf(node_dist, obs_val)
                    println(
                        "Added log probability for ", node, ": ", logpdf(node_dist, obs_val)
                    )
                end
            end
            return log_p
        else
            println("Starting marginalization")
            # Marginalize over discrete nodes
            likelihood = marginalize_recursive(nodes_to_marginalize, known_values)
            println("Final likelihood: ", likelihood)
            return log(likelihood)
        end
    end

    return log_posterior
end

# Updated evaluate_model function with more specific type annotations
function evaluate_model(
    net::BayesNet, observations::Dict{Symbol,Float64}, X1_values, description
)
    println("\n=== $description ===")
    println("Observations: ", observations)

    log_posterior_fn = create_log_posterior(net, observations)
    results = [(x1, log_posterior_fn(Dict(:X1 => x1))) for x1 in X1_values]
    max_log_p = maximum(last.(results))
    normalized = [(x1, exp(log_p - max_log_p)) for (x1, log_p) in results]

    for (x1, p) in normalized
        @printf("X1 = %.1f: %.4f\n", x1, p)
    end
end

# Convert existing models to BayesNet
model1 = create_bayes_net(
    Dict{Symbol,Any}(
        :X1 => Uniform(0, 1),
        :X2 => x1 -> Bernoulli(x1),
        :X3 => x2 -> Normal(x2 == 1 ? 9.0 : 7.0, 2.0),
    ),
    Dict{Symbol,Vector{Symbol}}(:X1 => Symbol[], :X2 => [:X1], :X3 => [:X2]),
)

# Create a mixed variable model
model_mixed = create_bayes_net(
    Dict{Symbol,Any}(
        :X1 => Normal(0, 1),                              # X1 is continuous
        :X2 => x1 -> Bernoulli(logistic(x1)),            # X2 is discrete (binary)
        :X3 => x2 -> Normal(x2 == 1 ? 2.0 : -2.0, 1.0),   # X3 is continuous
    ),
    Dict{Symbol,Vector{Symbol}}(:X1 => Symbol[], :X2 => [:X1], :X3 => [:X2]),
)

# Test cases demonstrating marginalization
X1_values = -2.0:0.5:2.0
# Case 1: Observe only X3, X2 will be marginalized out
evaluate_model(
    model_mixed, Dict(:X3 => 1.5), X1_values, "Mixed Model (X3 = 1.5, marginalizing X2)"
)
# Case 2: Observe both X2 and X3 for comparison
evaluate_model(
    model_mixed, Dict(:X2 => 1.0, :X3 => 1.5), X1_values, "Mixed Model (X2 = 1, X3 = 1.5)"
)

# Example usage
X1_values = 0.1:0.1:0.9
evaluate_model(model1, Dict(:X3 => 8.5), X1_values, "BayesNet Model (X3 ≈ 9.0)")

# Create a 4-node model
model_4_nodes = create_bayes_net(
    Dict{Symbol,Any}(
        :X1 => Normal(0, 1),
        :X2 => x1 -> Bernoulli(logistic(x1)),
        :X3 => x2 -> Normal(x2 == 1 ? 2.0 : -2.0, 1.0),
        :X4 => (x2, x3) -> Normal(x2 == 1 ? x3 + 1 : x3 - 1, 0.5),
    ),
    Dict{Symbol,Vector{Symbol}}(
        :X1 => Symbol[], :X2 => [:X1], :X3 => [:X2], :X4 => [:X2, :X3]
    ),
)

# Test cases for 4-node model
X1_values = -2.0:0.5:2.0

# Case 1: Observe X3 and X4, marginalize over X2 only
evaluate_model(
    model_4_nodes,
    Dict(:X3 => 1.0, :X4 => 1.0),
    X1_values,
    "4-Node Model (X3 = 1.0, X4 = 1.0, marginalizing X2)",
)

# Case 2: Observe all downstream variables
evaluate_model(
    model_4_nodes,
    Dict(:X2 => 1.0, :X3 => 1.0, :X4 => 1.0),
    X1_values,
    "4-Node Model (X2 = 1, X3 = 1.0, X4 = 1.0)",
)

# Test with a 5-node model that has multiple discrete nodes
model_5_nodes = create_sequential_net_n([
    Normal(0, 1),                              # X1 (continuous)
    x1 -> Bernoulli(logistic(x1)),            # X2 (discrete)
    x2 -> Bernoulli(x2 == 1 ? 0.7 : 0.3),     # X3 (discrete)
    x3 -> Bernoulli(x3 == 1 ? 0.8 : 0.2),     # X4 (discrete)
    x4 -> Normal(x4 == 1 ? 3.0 : -3.0, 1.0),   # X5 (continuous)
])

# Test cases
X1_values = -2.0:0.5:2.0

println("\n=== Testing multiple discrete marginalization ===")

# Case 1: Marginalize over X2 and X3, observe X4 and X5
evaluate_model(
    model_5_nodes,
    Dict(:X4 => 1.0, :X5 => 2.0),
    X1_values,
    "5-Node Model (X4=1.0, X5=2.0, marginalizing X2,X3)",
)

# Case 2: Marginalize over X2, X3, and X4, observe only X5
evaluate_model(
    model_5_nodes,
    Dict(:X5 => 2.0),
    X1_values,
    "5-Node Model (X5=2.0, marginalizing X2,X3,X4)",
)

# Case 3: Observe all variables (no marginalization)
evaluate_model(
    model_5_nodes,
    Dict(:X2 => 1.0, :X3 => 1.0, :X4 => 1.0, :X5 => 2.0),
    X1_values,
    "5-Node Model (all observed)",
)
