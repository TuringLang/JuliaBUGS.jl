struct DependencyGraph <: CompilerPass
    vars::Vars
    array_map::Dict
    dep_graph::SimpleDiGraph
end
function DependencyGraph(vars::Vars, arrays_map::Dict)
    dep_graph = SimpleDiGraph(length(vars))
    return DependencyGraph(vars, arrays_map, dep_graph)
end

lhs(::DependencyGraph, expr, env::Dict) = find_variables_on_lhs(expr, env)

"""
    rhs_variables(::DependencyGraph, expr, env)

Collect all variables in `expr` and return a `Set` of `Var`s.

# Examples
```julia-repl
julia> rhs_variables(DependencyGraph(), :(x[y[1] + 1, a, 2] + 1), Dict())
Set{Any} with 3 elements:
  a
  y[1]
  x[0, 0, 2]
"""
rhs(::DependencyGraph, expr::Number, ::Dict) = Set()
rhs(::DependencyGraph, expr::AbstractRange, ::Dict) = Set(nothing)
rhs(::DependencyGraph, expr::Symbol, ::Dict) = Set([Var(expr)])
function rhs(pass::DependencyGraph, expr::Expr, env::Dict)
    evaluated_expr = eval(expr, env)
    evaluated_expr isa Distributions.Distribution && return Set()
    evaluated_expr isa Number && return Set()
    evaluated_expr isa Symbol && return Set([Var(evaluated_expr)])
    if Meta.isexpr(evaluated_expr, :ref) &&
        all(x -> x isa Number || x isa UnitRange, evaluated_expr.args[2:end])
        return Set([Var(evaluated_expr.args[1], evaluated_expr.args[2:end])])
    end

    vars = Set()
    if Meta.isexpr(evaluated_expr, :call)
        for arg in evaluated_expr.args[2:end]
            union!(vars, rhs(pass, arg, env))
        end
        return vars
    else # then it's a :ref expression
        idxs = deepcopy(evaluated_expr.args[2:end])
        idxs[findall(x -> !isa(x, Number) || !isa(x, UniteRange), idxs)] .= 0 # mark the dimensions with variable indexing
        push!(vars, Var(evaluated_expr.args[1], idxs)) # dimension with variable indexing is set to 0
        for idx in evaluated_expr.args[2:end]
            union!(vars, rhs(pass, idx, env))
        end
        return vars
    end
end

function assignment!(pass::DependencyGraph, expr::Expr, env::Dict)
    vars, arrays_map = pass.vars, pass.array_map
    l_var = lhs(pass, expr.args[1], env)
    l_id = vars[l_var]
    scalarized_l_ids = [vars[v] for v in vcat(scalarize(l_var))]
    for l in scalarized_l_ids
        add_edge!(pass.dep_graph, l_id, l)
    end
    r_vars = collect(rhs(pass, expr.args[2], env))
    r_ids = []
    for r_var in r_vars
        if r_var isa Scalar
            push!(r_ids, vars[r_var])
        else
            idxs = Any[]
            for i in eachindex(r_var.indices)
                if r_var.indices[i] == 0
                    push!(idxs, Colon())
                else
                    push!(idxs, r_var.indices[i])
                end
            end
            for r_id in Iterators.flatten(arrays_map[r_var.name][idxs...])
                push!(r_ids, r_id)
            end
        end
    end
    for r_id in r_ids
        add_edge!(pass.dep_graph, r_id, l_id)
    end
end

function post_process(pass::DependencyGraph)
    for v in keys(pass.vars)
        if v isa ArrayVariable
            scalarized_v = scalarize(v)
            for s in scalarized_v
                has_edge(pass.dep_graph, pass.vars[v], pass.vars[s]) && continue
                add_edge!(pass.dep_graph, pass.vars[s], pass.vars[v])
            end
        end
    end
    return pass.dep_graph
end
