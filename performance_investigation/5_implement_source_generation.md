Here we implement the dependency graph and source generation discussed in 4.

```julia
using MacroTools
```

## Build Dependency Graph

First, we give each statement an id.

```julia
function _build_statement_id_map(expr, stmt_ids=IdDict{Expr, Int}(), id_counter=1)
    for stmt in expr.args
        if Meta.isexpr(stmt, (:(=), :call))
            stmt_ids[stmt] = id_counter
            id_counter += 1
        elseif Meta.isexpr(stmt, :for)
            id_counter, stmt_ids = _build_statement_id_map(stmt.args[2], stmt_ids, id_counter)
        end
    end
    return id_counter, stmt_ids
end
```

```julia
id_counter, stmt_ids = _build_statement_id_map(model_def)
stmt_ids
```

Next, we attribute each variable in the graph with the statement it comes from

```julia
struct AttributeStatementIdPass <: JuliaBUGS.CompilerPass
    stmt_ids::IdDict{Expr, Int}
    vn_to_stmt_id::Dict
    env::NamedTuple
end

using JuliaBUGS: is_deterministic, simplify_lhs, analyze_block
function JuliaBUGS.analyze_statement(pass::AttributeStatementIdPass, expr::Expr, loop_vars)
    lhs_expr = is_deterministic(expr) ? expr.args[1] : expr.args[2]
    env = merge(pass.env, loop_vars)
    v = simplify_lhs(env, lhs_expr)
    vn = if v isa Symbol
        JuliaBUGS.VarName{v}()
    else
        JuliaBUGS.VarName{v[1]}(JuliaBUGS.IndexLens(v[2:end]))
    end
    pass.vn_to_stmt_id[vn] = pass.stmt_ids[expr]
end
```

```julia
pass = AttributeStatementIdPass(stmt_ids, Dict(), model.evaluation_env)
analyze_block(pass, model_def)
pass.vn_to_stmt_id
```

Finally, we can build the dependency graph

```julia
stmt_dep_graph = Graphs.SimpleDiGraph(length(keys(stmt_ids)))

# reverse lookup
stmt_ids_to_vn = Dict()
for (vn, stmt_id) in pass.vn_to_stmt_id
    if !haskey(stmt_ids_to_vn, stmt_id)
        stmt_ids_to_vn[stmt_id] = [vn]
    else
        push!(stmt_ids_to_vn[stmt_id], vn)
    end
end

for (stmt1, stmt2) in Iterators.product(1:length(stmt_ids), 1:length(stmt_ids))
    for (vn1, vn2) in Iterators.product(stmt_ids_to_vn[stmt1], stmt_ids_to_vn[stmt2])
        if vn2 in MetaGraphsNext.inneighbor_labels(model.g, vn1)
            Graphs.add_edge!(stmt_dep_graph, stmt2, stmt1)
        elseif vn1 in MetaGraphsNext.inneighbor_labels(model.g, vn2)
            Graphs.add_edge!(stmt_dep_graph, stmt1, stmt2)
        end
    end
end

collect(Graphs.edges(stmt_dep_graph))
```

```julia
function _build_stmt_dep_graph(stmt_ids, model, model_def)
    # Create graph with number of statements as nodes
    stmt_dep_graph = Graphs.SimpleDiGraph(length(keys(stmt_ids)))

    # Create pass to analyze statements and get variable name to statement ID mapping
    pass = AttributeStatementIdPass(stmt_ids, Dict(), model.evaluation_env)
    analyze_block(pass, model_def) # TODO: use `model.model_def` can error because of IdDict, there must be a deepcopy somewhere
    
    # Build reverse lookup from statement ID to variable names
    stmt_ids_to_vn = Dict()
    for (vn, stmt_id) in pass.vn_to_stmt_id
        if !haskey(stmt_ids_to_vn, stmt_id)
            stmt_ids_to_vn[stmt_id] = [vn]
        else
            push!(stmt_ids_to_vn[stmt_id], vn)
        end
    end

    # Add edges based on dependencies in model graph
    for (stmt1, stmt2) in Iterators.product(1:length(stmt_ids), 1:length(stmt_ids))
        for (vn1, vn2) in Iterators.product(stmt_ids_to_vn[stmt1], stmt_ids_to_vn[stmt2])
            if vn2 in MetaGraphsNext.inneighbor_labels(model.g, vn1)
                Graphs.add_edge!(stmt_dep_graph, stmt2, stmt1)
            elseif vn1 in MetaGraphsNext.inneighbor_labels(model.g, vn2)
                Graphs.add_edge!(stmt_dep_graph, stmt1, stmt2)
            end
        end
    end

    return stmt_dep_graph
end

```

```julia
Graphs.has_self_loops(stmt_dep_graph) # self cycle
Graphs.simplecycles(stmt_dep_graph) # simple cycle
```

---
verify with one of the previous example

```julia
m_d = @bugs begin
    x[1] ~ dnorm(0, 1)
    
    sumX[1] = x[1]
    for i in 2:4
        sumX[i] = sumX[i-1] + x[i]
    end

    for i in 2:4
        x[i] ~ dnorm(sumX[i-1], 1)
    end
end

m = compile(m_d, (;))
```

```julia
_, m_stmt_ids = _build_statement_id_map(m_d)
m_dep_graph = _build_stmt_dep_graph(stmt_ids, m, m_d)
```

```julia
Graphs.simplecycles(m_dep_graph) # contain cycles
```

---

## generate code

Recall that the edge of dependency graph means that if we finish all the computation of the statements associated with the target statement, then all the computation of the terminal statement are safe to run.

So when generating source, we first fission all the loops.

```julia
function _fission_loop(expr, stmt_ids, current_loop=(), fissioned_stmts=[])
    for stmt in expr.args
        if Meta.isexpr(stmt, (:(=), :call))
            push!(fissioned_stmts, (current_loop, stmt))
        elseif Meta.isexpr(stmt, :for)
            MacroTools.@capture(stmt.args[1], loop_var_ = l_:h_)
            l = JuliaBUGS.simple_arithmetic_eval(model.evaluation_env, l)
            h = JuliaBUGS.simple_arithmetic_eval(model.evaluation_env, h)
            _fission_loop(stmt.args[2], stmt_ids, (current_loop..., (loop_var, l, h)), fissioned_stmts)
        end
    end
    return fissioned_stmts
end

fissioned_stmts = _fission_loop(model_def, stmt_ids)
```

```julia
11-element Vector{Any}:
 (((:i, 1, 30), (:j, 1, 5)), :(Y[i, j] ~ dnorm(mu[i, j], var"tau.c")))
 (((:i, 1, 30), (:j, 1, 5)), :(mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)))
 (((:i, 1, 30),), :(alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")))
 (((:i, 1, 30),), :(beta[i] ~ dnorm(var"beta.c", var"beta.tau")))
 ((), :(var"tau.c" ~ dgamma(0.001, 0.001)))
 ((), :(sigma = 1 / sqrt(var"tau.c")))
 ((), :(var"alpha.c" ~ dnorm(0.0, 1.0e-6)))
 ((), :(var"alpha.tau" ~ dgamma(0.001, 0.001)))
 ((), :(var"beta.c" ~ dnorm(0.0, 1.0e-6)))
 ((), :(var"beta.tau" ~ dgamma(0.001, 0.001)))
 ((), :(alpha0 = var"alpha.c" - xbar * var"beta.c"))
```

the fission function is written in a similar way as the statement id assignment function, so the order of `fissioned_stmts` follows `stmt_ids`.

Then we can do a topological sort and generate a sequential version,

```julia
sorted_stmts = Graphs.topological_sort(stmt_dep_graph)

sorted_fissioned_stmts = []
for stmt_id in sorted_stmts
    for (loops, stmt) in fissioned_stmts
        if stmt_ids[stmt] == stmt_id
            push!(sorted_fissioned_stmts, (loops, stmt))
        end
    end
end
sorted_fissioned_stmts

function _gen_seq_version(fissioned_stmts)
    args = []
    for (loops, stmt) in fissioned_stmts
        if loops == ()
            push!(args, stmt)
        else
            push!(args, _gen_loop_expr(loops, stmt))
        end
    end
    return Expr(:block, args...)
end

function _gen_loop_expr(loop_vars, stmt)
    loop_var, l, h = loop_vars[1]
    if length(loop_vars) == 1
        return MacroTools.@q for $(loop_var) in $(l):$(h)
            $(stmt)
        end
    else
        return MacroTools.@q for $(loop_var) in $(l):$(h)
            $(_gen_loop_expr(loop_vars[2:end], stmt))
        end
    end
end

seq_expr = _gen_seq_version(sorted_fissioned_stmts)

```

Next we proceed to generate a log joint density evaluation function from a sequential program.

The first step is to figure out if a stochastic statement are all observations or model parameters (**we don't support mixed case now**).

```julia
stmt_id_to_types = Dict()
for (k, vns) in stmt_ids_to_vn
    # not memory efficient
    function var_type(model, vn)
        if model.g[vn].is_stochastic
            if model.g[vn].is_observed
                return :observed
            else
                return :model_parameter
            end
        else
            return :deterministic
        end
    end
    vn_types = [var_type(model, vn) for vn in vns]
    if !all(==(vn_types[1]), vn_types)
        error("Mixed variable types in statement: $(vn_types)")
    end
    stmt_id_to_types[k] = vn_types[1]
end
stmt_to_type = IdDict()
for (k, v) in stmt_ids
    stmt_to_type[k] = stmt_id_to_types[v]
end
stmt_to_type

```

```julia
function _gen_logp_eval_code(model_def, stmt_to_type, stmt_to_range)
    exs = Expr[]
    for arg in model_def.args
        if Meta.isexpr(arg, :for)
            push!(exs, Expr(:for, arg.args[1], _gen_logp_eval_code(arg.args[2], stmt_to_type, stmt_to_range)))
        elseif arg in collect(keys(stmt_to_type))
            if stmt_to_type[arg] == :observed
                push!(exs, _gen_observation_expr(arg))
            elseif stmt_to_type[arg] == :model_parameter
                push!(exs, _gen_model_parameter_expr(arg, stmt_to_range))
            else
                push!(exs, _gen_deterministic_expr(arg))
            end
        end
    end
    return Expr(:block, exs...)
end

function _gen_observation_expr(expr)
    if MacroTools.@capture(expr, lhs_ ~ rhs_)
        return :(__logp__ += logpdf($(esc(rhs)), $(esc(lhs))))
    else
        error()
    end
end

function _gen_deterministic_expr(expr)
    if MacroTools.@capture(expr, lhs_ = rhs_)
        return expr
    else
        error()
    end
end

function _build_stmt_to_range(model, stmt_ids_to_vn, id_to)
    var_lengths = model.transformed_var_lengths
    stmt_id_to_range = Dict{Int, Tuple{Int, Int}}()
    current_idx = 1
    
    for (stmt_id, vns) in stmt_ids_to_vn
        if stmt_id_to_types[stmt_id] == :model_parameter
            total_length = sum(var_lengths[vn] for vn in vns)
            stmt_id_to_range[stmt_id] = (current_idx, current_idx + total_length - 1)
            current_idx += total_length
        end
    end
    
    return stmt_id_to_range
end

stmt_id_to_range = _build_stmt_to_range(model, stmt_ids_to_vn)
stmt_to_range = IdDict()
for (stmt, stmt_id) in stmt_ids
    if haskey(stmt_id_to_range, stmt_id)
        stmt_to_range[stmt] = stmt_id_to_range[stmt_id]
    end
end
stmt_to_range

function _gen_model_parameter_expr(expr, stmt_to_range)
    if MacroTools.@capture(expr, lhs_ ~ rhs_)
        return MacroTools.@q begin
            __dist__  = $rhs
            __b__ = Bijectors.bijector(__dist__)
            __b_inv__ = Bijectors.inverse(__b__)
            __reconstructed_value__ = JuliaBUGS.reconstruct(__b_inv__, __dist__, view(__flattened_values__, __start_idx__:__end_idx__))
            (__value__, __logjac__) = Bijectors.with_logabsdet_jacobian(__b_inv__, __reconstructed_value__)
            __logprior__ = Distributions.logpdf(__dist__, __value__) + __logjac__
            __logp__ =+ logprior
            $lhs = __value
        end
    else
        error()
    end
end
```

```julia
_gen_logp_eval_code(seq_expr, stmt_to_type, stmt_to_range)
```

