using Distributions, Printf

#####################
# 1. Factor Structure
#####################

struct Factor
    scope::Vector{Symbol}
    fn::Function
end

function factor_value(f::Factor, assignment::Dict{Symbol,Any})
    vals = map(v -> assignment[v], f.scope)
    return f.fn(vals...)
end

#####################
# 2. Factor Operations
#####################

function multiply_factors(fA::Factor, fB::Factor)
    new_scope = union(fA.scope, fB.scope)
    sort!(new_scope, by=x->string(x))

    function new_fn(args...)
        assignment = Dict{Symbol,Any}()
        for (i, var) in enumerate(new_scope)
            assignment[var] = args[i]
        end
        return factor_value(fA, assignment) * factor_value(fB, assignment)
    end

    return Factor(new_scope, new_fn)
end

function sum_out(f::Factor, var_to_eliminate::Symbol, domain::Vector{Any})
    new_scope = filter(x -> x != var_to_eliminate, f.scope)
    function new_fn(args...)
        partial_assignment = Dict{Symbol,Any}()
        for (i, var) in enumerate(new_scope)
            partial_assignment[var] = args[i]
        end
        total = 0.0
        for val in domain
            extended_assignment = copy(partial_assignment)
            extended_assignment[var_to_eliminate] = val
            total += factor_value(f, extended_assignment)
        end
        return total
    end
    return Factor(new_scope, new_fn)
end

function condition_factor(f::Factor, varname::Symbol, obs_value::Any)
    if !(varname in f.scope)
        return f
    end
    new_scope = filter(x -> x != varname, f.scope)
    function new_fn(args...)
        assignment = Dict{Symbol,Any}()
        for (i, v) in enumerate(new_scope)
            assignment[v] = args[i]
        end
        assignment[varname] = obs_value
        return factor_value(f, assignment)
    end
    return Factor(new_scope, new_fn)
end

#############################
# 3. Define 5-Node Chain Factors
#############################

function create_5node_factors()
    logistic(x) = 1 / (1 + exp(-x))

    f1 = Factor(
        [:X1],
        (x1,) -> pdf(Normal(0,1), x1)
    )

    f2 = Factor(
        [:X1, :X2],
        (x1, x2) -> begin
            p = logistic(x1)
            return x2 == 1 ? p : (1 - p)
        end
    )

    f3 = Factor(
        [:X2, :X3],
        (x2, x3) -> begin
            p = (x2 == 1) ? 0.7 : 0.3
            return x3 == 1 ? p : (1 - p)
        end
    )

    f4 = Factor(
        [:X3, :X4],
        (x3, x4) -> begin
            p = (x3 == 1) ? 0.8 : 0.2
            return x4 == 1 ? p : (1 - p)
        end
    )

    f5 = Factor(
        [:X4, :X5],
        (x4, x5) -> begin
            dist = (x4 == 1) ? Normal(3.0,1.0) : Normal(-3.0,1.0)
            return pdf(dist, x5)
        end
    )

    return [f1, f2, f3, f4, f5]
end

#############################
# 4. Naive Variable Elimination
#############################

function naive_variable_elimination(
    factors::Vector{Factor},
    observed::Dict{Symbol,Any},
    elimination_order::Vector{Symbol},
    domains::Dict{Symbol,Vector{Any}}
)
    # Condition on observations
    for (obs_var, obs_val) in observed
        for i in 1:length(factors)
            factors[i] = condition_factor(factors[i], obs_var, obs_val)
        end
    end

    # Sum out variables in elimination_order
    for v in elimination_order
        involved = [f for f in factors if v in f.scope]
        if isempty(involved)
            continue
        end
        new_factor = reduce(multiply_factors, involved)
        factors = setdiff(factors, involved)
        new_factor = sum_out(new_factor, v, domains[v])
        push!(factors, new_factor)
    end

    final_factor = reduce(multiply_factors, factors; init=Factor([], x->1.0))
    return final_factor
end

#############################
# 5. Demonstration on 5-Node Chain
#############################

function demo_5node_factor_based()
    # Create factors for the 5-node chain
    factors = create_5node_factors()

    # Observations for X4 and X5
    observed = Dict(:X4 => 1, :X5 => 2.0)

    # Domains for discrete variables we plan to sum out
    domains = Dict(
        :X2 => [0,1],
        :X3 => [0,1]
    )

    # Elimination order for unobserved discrete variables: X2, X3
    elimination_order = [:X2, :X3]

    # Run naive variable elimination
    final_factor = naive_variable_elimination(factors, observed, elimination_order, domains)

    println("Final factor scope = ", final_factor.scope)
    println("The final factor is proportional to P(X1, X4=1, X5=2).")

    # To approximate P(X1 | X4=1, X5=2), evaluate the final factor over a grid for X1
    X1_grid = [0.0, 0.5, 1.0, 1.5, 2.0]
    vals = Float64[]
    for x1 in X1_grid
        assignment = Dict(:X1 => x1)
        push!(vals, factor_value(final_factor, assignment))
    end

    total = sum(vals)
    normalized = vals ./ total

    println("\nApproximate P(X1 | X4=1, X5=2):")
    for (i, x1) in enumerate(X1_grid)
        @printf("  X1=%.1f => %.5f\n", x1, normalized[i])
    end
end

# Run the demonstration
demo_5node_factor_based()
