"""
    eval(expr, env)

Evaluate `expr` in the environment `env`.

# Examples
```jldoctest
julia> eval(:(x[1]), Dict(:x => [1, 2, 3])) # array indexing is evaluated if possible
1

julia> eval(:(x[1] + 1), Dict(:x => [1, 2, 3]))
2

julia> eval(:(x[1:2]), Dict()) |> Meta.show_sexpr # ranges are evaluated
(:ref, :x, 1:2)

julia> eval(:(x[1:2]), Dict(:x => [1, 2, 3])) # ranges are evaluated
2-element Vector{Int64}:
 1
 2

julia> eval(:(x[1:3]), Dict(:x => [1, 2, missing])) # if an element is missing, the partially evaluated ref expr is returned as is
:(x[1:3])

julia> eval(:(x[y[z[1] + 1] + 1] + 2), Dict()) # if a ref expr can't be evaluated, it's returned as is
:(x[y[z[1] + 1] + 1] + 2)

julia> JuliaBUGS.eval(:(dnorm(x[y[1] + 1] + 1, 2)), Dict()) # function calls 
:(dnorm(x[y[1] + 1] + 1, 2))
"""
eval(var::Number, ::Any) = var
eval(var::UnitRange, ::Dict) = var
eval(::Colon, ::Dict) = Colon()
function eval(var::Symbol, env::Dict) 
    var == :(:) && return Colon()
    return haskey(env, var) ? env[var] : var
end
function eval(var::Expr, env::Dict)
    if Meta.isexpr(var, :ref)
        MacroTools.postwalk(var) do sub_expr
            if Meta.isexpr(sub_expr, :call) && !in(sub_expr.args[1], [:+, :-, :*, :/, :(:)])
                error("At $sub_expr: Only +, -, *, / are allowed in indexing.")
            end
            return sub_expr
        end
        idxs = (ex -> eval(ex, env)).(var.args[2:end])
        if all(x -> x isa Union{Number, UnitRange, Colon}, idxs) && haskey(env, var.args[1])
            value = getindex(env[var.args[1]], idxs...)
            if value isa Array && any(ismissing, value)
                return Expr(:ref, var.args[1], idxs...)
            end
            return ismissing(value) ? Expr(:ref, var.args[1], idxs...) : value
        end
        return Expr(:ref, var.args[1], idxs...)
    else
        args = map(ex -> eval(ex, env), var.args[2:end])
        var_with_evaled_arg = Expr(var.head, var.args[1], args...)
        evaled_var = var_with_evaled_arg
        try evaled_var = eval(var_with_evaled_arg) catch end
        return evaled_var
    end
end
