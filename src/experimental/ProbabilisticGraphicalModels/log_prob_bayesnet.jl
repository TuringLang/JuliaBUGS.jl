using Distributions
using Printf

# Add logistic function definition
logistic(x) = 1 / (1 + exp(-x))

# New BayesNet structure
struct BayesNet{T}
    nodes::Dict{Symbol, T}  # Distribution or function returning distribution
    edges::Dict{Symbol, Vector{Symbol}}  # Child -> Parents
end

# Helper to create a BayesNet
function create_bayes_net(nodes::Dict{Symbol, Any}, edges::Dict{Symbol, Vector{Symbol}})
    BayesNet(nodes, edges)
end

# Updated log_posterior function with Float64 type specification
function create_log_posterior(net::BayesNet{T}, observations::Dict{Symbol,Float64}) where T
    function log_posterior(values::Dict{Symbol,Float64})
        log_p = 0.0
        
        # Create a combined dict of all known values
        known_values = merge(values, observations)
        
        # Evaluate each node given its parents
        for (node, dist) in net.nodes
            if haskey(observations, node)
                # Observed node
                parents = get(net.edges, node, Symbol[])
                if !isempty(parents) && !all(p -> haskey(known_values, p), parents)
                    # Skip if we don't have all parent values
                    continue
                end
                parent_values = [known_values[p] for p in parents]
                node_dist = parents == [] ? dist : dist(parent_values...)
                log_p += logpdf(node_dist, observations[node])
            elseif !haskey(values, node)
                # Marginalize over unobserved intermediate variables
                parents = get(net.edges, node, Symbol[])
                if !isempty(parents) && !all(p -> haskey(known_values, p), parents)
                    # Skip if we don't have all parent values
                    continue
                end
                parent_values = [known_values[p] for p in parents]
                node_dist = parents == [] ? dist : dist(parent_values...)
                
                if node_dist isa DiscreteDistribution
                    likelihood = 0.0
                    for val in support(node_dist)
                        p_node = pdf(node_dist, val)
                        # Recursively compute probability of children
                        child_nodes = [k for (k,v) in net.edges if node in v]
                        for child in child_nodes
                            if haskey(observations, child)
                                child_parents = net.edges[child]
                                # Create temporary values dict with current marginalization value
                                temp_values = copy(known_values)
                                temp_values[node] = val
                                child_parent_values = [temp_values[p] for p in child_parents]
                                child_dist = net.nodes[child](child_parent_values...)
                                p_node *= pdf(child_dist, observations[child])
                            end
                        end
                        likelihood += p_node
                    end
                    log_p += log(likelihood)
                else
                    error("Currently only supporting discrete intermediate variables")
                end
            end
        end
        return log_p
    end
    return log_posterior
end

# Updated evaluate_model function with more specific type annotations
function evaluate_model(net::BayesNet, observations::Dict{Symbol,Float64}, X1_values, description)
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
    Dict{Symbol, Any}(
        :X1 => Uniform(0, 1),
        :X2 => x1 -> Bernoulli(x1),
        :X3 => x2 -> Normal(x2 == 1 ? 9.0 : 7.0, 2.0)
    ),
    Dict{Symbol, Vector{Symbol}}(
        :X1 => Symbol[],
        :X2 => [:X1],
        :X3 => [:X2]
    )
)

# Create a mixed variable model
model_mixed = create_bayes_net(
    Dict{Symbol, Any}(
        :X1 => Normal(0, 1),                              # X1 is continuous
        :X2 => x1 -> Bernoulli(logistic(x1)),            # X2 is discrete (binary)
        :X3 => x2 -> Normal(x2 == 1 ? 2.0 : -2.0, 1.0)   # X3 is continuous
    ),
    Dict{Symbol, Vector{Symbol}}(
        :X1 => Symbol[],
        :X2 => [:X1],
        :X3 => [:X2]
    )
)

# Test cases demonstrating marginalization
X1_values = -2.0:0.5:2.0
# Case 1: Observe only X3, X2 will be marginalized out
evaluate_model(model_mixed, Dict(:X3 => 1.5), X1_values, "Mixed Model (X3 = 1.5, marginalizing X2)")
# Case 2: Observe both X2 and X3 for comparison
evaluate_model(model_mixed, Dict(:X2 => 1.0, :X3 => 1.5), X1_values, "Mixed Model (X2 = 1, X3 = 1.5)")

# Example usage
X1_values = 0.1:0.1:0.9
evaluate_model(model1, Dict(:X3 => 8.5), X1_values, "BayesNet Model (X3 ≈ 9.0)")

# Create a 4-node model
model_4_nodes = create_bayes_net(
    Dict{Symbol, Any}(
        :X1 => Normal(0, 1),
        :X2 => x1 -> Bernoulli(logistic(x1)),
        :X3 => x2 -> Normal(x2 == 1 ? 2.0 : -2.0, 1.0),
        :X4 => (x2, x3) -> Normal(x2 == 1 ? x3 + 1 : x3 - 1, 0.5)
    ),
    Dict{Symbol, Vector{Symbol}}(
        :X1 => Symbol[],
        :X2 => [:X1],
        :X3 => [:X2],
        :X4 => [:X2, :X3]
    )
)

# Test cases for 4-node model
X1_values = -2.0:0.5:2.0

# Case 1: Observe X3 and X4, marginalize over X2 only
evaluate_model(model_4_nodes, Dict(:X3 => 1.0, :X4 => 1.0), X1_values, 
    "4-Node Model (X3 = 1.0, X4 = 1.0, marginalizing X2)")

# Case 2: Observe all downstream variables
evaluate_model(model_4_nodes, Dict(:X2 => 1.0, :X3 => 1.0, :X4 => 1.0), X1_values, 
    "4-Node Model (X2 = 1, X3 = 1.0, X4 = 1.0)")