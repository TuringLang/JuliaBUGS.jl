# The Refactored Compiler

## `evaluate`s

- `simplify_lhs` (which calls `simplify_lhs_eval` on the indices)
  - LHS can only be `Symbol` or a `Expr(:ref, ...)`
  - In the latter case, the indices can be arithmetic expressions
    - Only allow functions: `+, -, *` (currently also allow `/` but maybe shouldn't as it produces `Float64`)
    - Can contain array indexing to data arrays and use these values in the arithmetic expressions
  - `simplify_lhs_eval` is a simple and restrictive evaluation function
    - Its performance still rather slow compare to compiled code, but at least in the first pass, we can trade performance with customized behaviors
  - We want to check the indices to decide the size of the arrays, so we need to evaluate the indices
    - **The expressions must evaluate to either `Int` or `UnitRange`.**

```julia
# struct NodeInfo end

# function build_graph(state::CompileState)
#     return g = MetaGraph(DiGraph(), VarName, NodeInfo)
# end

# build coarse graph

function build_coarse_dependency_graph(state::CompileState)
    g = MetaGraph(
        DiGraph();
        label_type=Symbol,
        vertex_data_type=Union{Nothing, <:MetaGraph} # represented contracted node
        edge_data_type=Union{Statement,ForStatement},
        graph_data="Coarse Graph",
    )
    for statement in vcat(
        state.logical_statements,
        state.logical_for_statements,
        state.stochastic_statements,
        state.stochastic_for_statements,
    )
        lhs_var = statement.lhs isa Symbol ? statement.lhs : statement.lhs.args[1]
        add_vertex!(g, lhs_var, nothing)

        for rhs_var in statement.rhs_vars
            add_vertex!(g, rhs_var, nothing)
            add_edge!(g, rhs_var, lhs_var, statement)
        end
    end
    return g
end

function contract_until_dag(g::MetaGraph)

end

# the core is that for a graph contains loops, we can contract the cycle basis to a single node
# and then the graph becomes a DAG

# how many types of variables are there
# scalar, array variable, sub-graphs

# ! what do we want?
# efficiently compute the dependency structure
# the most accurate dependency requires building the graph
# but nice thing is that as long as the dependency contains all the variable in the MB, it is correct
# abstract interpretation?



g = build_coarse_dependency_graph(state)

# generate code to plot graph in pure text using print
for v in labels(g)
    println(v)
    for e in MetaGraphsNext.outneighbor_labels(g, v)
        println("  -> ", e)
    end
end

Graphs.is_cyclic(g.graph)

# the coarse graph is a possible graph via contraction 
Graphs.has_self_loops(g.graph)

# 
```

## taxonomy of BUGS programs according to easiness of dealing with

- all variables are scalars

- all array variables appear once and dependency is super clear
  - all indices are simple linear transformations of the loop variable
  - if two or more loop variables are involved, they do not appear in the same expression (for indexing)
  - no data in indices

  ```julia
  @bugs begin
      for i in 1:10
          x[i] ~ Normal(y[i], 1)
      end
  end
  ```
  
  - programs translated from a plate notation where all variables only appear once is in this case
