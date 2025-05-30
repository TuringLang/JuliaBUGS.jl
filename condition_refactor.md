# Condition Refactoring Plan

## Current Problems

The current `condition` function in `src/model/abstractppl.jl` is doing too much:

1. **Mixed Responsibilities**: The function is handling both:
   - Setting values for conditioned variables (updating `evaluation_env`)
   - Creating a subgraph/slice of the model (computing Markov blanket and filtering nodes)

2. **Limited Input Types**: Currently only supports:
   - `Dict{<:VarName, <:Any}` - dictionary of variable names to values
   - `Vector{<:VarName}` - vector of variable names (with values from evaluation_env)

3. **Tight Coupling**: The graph slicing logic (Markov blanket computation) is tightly coupled with the conditioning logic.

## Current Implementation Issues

### Issue 1: Overloaded Functionality
The `condition` function performs multiple operations:
```julia
# Lines 24-31: Computing Markov blanket and filtering nodes
sorted_blanket_with_vars = filter(
    vn -> vn in union(markov_blanket(model.g, new_parameters), new_parameters),
    model.flattened_graph_node_data.sorted_nodes,
)

# Lines 34-43: Marking variables as observed
for vn in sorted_blanket_with_vars
    if vn in new_parameters
        continue
    end
    ni = g[vn]
    if ni.is_stochastic && !ni.is_observed
        ni = @set ni.is_observed = true
        g[vn] = ni
    end
end

# Lines 45-48: Creating new model
new_model = BUGSModel(
    model, g, new_parameters, sorted_blanket_with_vars, evaluation_env
)
```

### Issue 2: Limited Flexibility
- Cannot condition on expressions or transformations of variables
- Cannot condition with different value specifications (e.g., constraints, distributions)
- Cannot easily reuse the graph slicing logic independently

## Proposed Refactoring

### 1. Separate Graph Slicing from Conditioning

Create a new function for creating subgraphs:
```julia
"""
    subgraph(model::BUGSModel, keep_vars::Vector{<:VarName}; 
             include_markov_blanket=true, sorted_nodes=Nothing)

Create a subgraph of the model containing only the specified variables 
and optionally their Markov blanket.
"""
function subgraph(model::BUGSModel, keep_vars::Vector{<:VarName}; 
                  include_markov_blanket=true, sorted_nodes=Nothing)
    # Compute nodes to keep
    nodes_to_keep = if include_markov_blanket
        union(markov_blanket(model.g, keep_vars), keep_vars)
    else
        keep_vars
    end
    
    # Filter and sort nodes
    sorted_nodes = filter(
        vn -> vn in nodes_to_keep,
        sorted_nodes === Nothing ? model.flattened_graph_node_data.sorted_nodes : sorted_nodes
    )
    
    # Create new graph (without modifying observation status)
    g_new = copy(model.g)
    # ... graph construction logic ...
    
    return BUGSModel(model, g_new, keep_vars, sorted_nodes, model.evaluation_env)
end
```

### 2. Simplify Condition Function

Make `condition` focus only on setting values and marking variables as observed:
```julia
function condition(model::BUGSModel, conditioning_spec)
    # Parse conditioning specification
    var_values, var_constraints = parse_conditioning_spec(conditioning_spec)
    
    # Update evaluation environment
    new_evaluation_env = update_evaluation_env(model.evaluation_env, var_values)
    
    # Mark conditioned variables as observed
    g_new = mark_as_observed(model.g, keys(var_values))
    
    # Create subgraph if needed (delegate to subgraph function)
    new_parameters = setdiff(model.parameters, keys(var_values))
    submodel = subgraph(model, new_parameters; include_markov_blanket=true)
    
    # Update with new evaluation environment and graph
    return BUGSModel(submodel, g_new, submodel.parameters, 
                     submodel.flattened_graph_node_data.sorted_nodes, 
                     new_evaluation_env)
end
```

### 3. Support Multiple Input Types

Create a flexible conditioning specification system:
```julia
# Support various input types
condition(model, Dict(:x => 1.0, :y => 2.0))  # Direct values
condition(model, :x => Normal(0, 1))           # Condition on distribution
condition(model, [:x, :y])                     # Use existing values
condition(model, :x => x -> x > 0)            # Constraints
condition(model, Pairs(:x => 1.0, :y => 2.0)) # Named arguments style
```

### 4. New Helper Functions

```julia
# Parse different conditioning specifications
function parse_conditioning_spec(spec)
    # Return (var_values::Dict, var_constraints::Dict)
end

# Update evaluation environment with new values
function update_evaluation_env(env::NamedTuple, var_values::Dict)
    # Return updated environment
end

# Mark variables as observed in graph
function mark_as_observed(g::BUGSGraph, vars::Vector{<:VarName})
    # Return new graph with marked observations
end
```

## Benefits of Refactoring

1. **Separation of Concerns**: Graph operations and conditioning logic are separated
2. **Reusability**: The `subgraph` function can be used independently for other purposes
3. **Flexibility**: Support for multiple conditioning specifications
4. **Maintainability**: Cleaner, more focused functions that are easier to test and modify
5. **Extensibility**: Easy to add new conditioning types without modifying core logic

## Implementation Steps

1. Implement `subgraph` function
2. Implement helper functions (`parse_conditioning_spec`, `update_evaluation_env`, `mark_as_observed`)
3. Refactor `condition` to use new functions
4. Add support for multiple input types
5. Update tests to cover new functionality
6. Update documentation

## Backward Compatibility

The refactored implementation should maintain backward compatibility with existing usage:
- `condition(model, dict)` should work as before
- `condition(model, vector)` should work as before
- Performance should not degrade