struct DependencyGraph <: CompilerPass 
    vars::Vars
    array_map::Dict
    dep_graph::SimpleDiGraph
end

function DependencyGraph(vars::Vars, array_map::Dict)
    dep_graph = SimpleDiGraph(length(vars.id_var_map))
    # connect array slicing to elements
    for k in keys(vars.var_id_map)
        if k isa ArraySlice || k isa ArrayVariable
            scarlarized_vars = scalarize(k)
            for sv in scarlarized_vars
                add_edge!(dep_graph, vars[sv], vars[k])
            end
        end
    end
    return DependencyGraph(vars, array_map, dep_graph)
end

lhs(::DependencyGraph, expr, env::Dict) = find_variables(expr, env)

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
function rhs(pass::DependencyGraph, expr::Expr, env::Dict)
    evaluated_expr = eval(expr, env)
    evaluated_expr isa Distributions.Distribution && return Set()
    evaluated_expr isa Number && return Set()
    evaluated_expr isa Symbol && return Set([Var(evaluated_expr)])
    if Meta.isexpr(evaluated_expr, :ref) && all(x -> x isa Number || x isa UnitRange, evaluated_expr.args[2:end])
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
rhs(::DependencyGraph, expr::Number, ::Dict) = nothing
rhs(::DependencyGraph, expr, env::Dict) = find_variables(expr, env)

function assignment!(pass::DependencyGraph, expr::Expr, env::Dict)
    vars, arrays_map = pass.vars, pass.array_map
    l_vars = collect(lhs(pass, expr.args[1], env))
    r_vars = collect(rhs(pass, expr.args[2], env))
    l_ids = [vars[v] for v in l_vars]
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
    for (l_id, r_id) in Iterators.product(l_ids, r_ids)
        add_edge!(pass.dep_graph, r_id, l_id)
    end
end

post_process(pass::DependencyGraph) = pass.dep_graph
