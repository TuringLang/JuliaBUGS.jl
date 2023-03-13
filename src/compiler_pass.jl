"""
    eval(expr, env)

Evaluate `expr` in the environment `env`.

#Examples
```julia-repl
julia> eval(:(x[1]), Dict(:x => [1, 2, 3])) # array indexing is evaluated if possible
1

julia> eval(:(x[1] + 1), Dict(:x => [1, 2, 3]))
2

julia> eval(:(x[1:2]), Dict(:x => [1, 2, 3])) |> dump # ranges are evaluated
Expr
  head: Symbol ref
  args: Array{Any}((2,))
    1: Symbol x
    2: UnitRange{Int64}
      start: Int64 1
      stop: Int64 2

julia> eval(:(x[y[z[1] + 1] + 1] + 2), Dict()) # if a ref expr can't be evaluated, it's returned as is
:(x[y[z[1] + 1] + 1] + 2)

julia> JuliaBUGS.eval(:(dnorm(x[y[1] + 1] + 1, 2)), Dict()) # function calls 
:(dnorm(x[y[1] + 1] + 1, 2))
"""
eval(var::Number, ::Any) = var
eval(var::UnitRange, ::Dict) = var
eval(var::Symbol, env::Dict) = haskey(env, var) && !ismissing(env[var]) ? env[var] : var
function eval(var::Expr, env::Dict)
    if Meta.isexpr(var, :ref)
        MacroTools.postwalk(var) do sub_expr
            if Meta.isexpr(sub_expr, :call) && !in(sub_expr.args[1], [:+, :-, :*, :/, :(:)])
                error("At $sub_expr: Only +, -, *, / are allowed in indexing.")
            end
            return sub_expr
        end
        idxs = (ex -> eval(ex, env)).(var.args[2:end])
        if all(x -> x isa Number || x isa UnitRange, idxs) && haskey(env, var.args[1])
            value = getindex(env[var.args[1]], idxs...)
            if ismissing(value)
                return Expr(:ref, var.args[1], idxs...)
            else
                return value
            end
        else
            return Expr(:ref, var.args[1], idxs...)
        end
    else
        args = map(ex -> eval(ex, env), var.args[2:end])
        var_with_evaled_arg = Expr(var.head, var.args[1], args...)
        evaled_var = var_with_evaled_arg
        try
            evaled_var = eval(var_with_evaled_arg)
        catch _ end

        if evaled_var isa Distributions.Distribution
            return var_with_evaled_arg
        else
            return evaled_var
        end
    end
end

"""
    CompilerPass

Abstract supertype for all compiler passes. Concrete subtypes should store data needed and artifacts.
"""
abstract type CompilerPass end

function program!(pass::CompilerPass, expr::Expr, env::Dict, vargs...)
    for ex in expr.args
        if Meta.isexpr(ex, [:(=), :(~)])
            assignment!(pass, ex, env, vargs...)
        elseif Meta.isexpr(ex, :for)
            for_loop!(pass, ex, env, vargs...)
        else
            error()
        end
    end
    return post_process(pass)
end

function for_loop!(pass::CompilerPass, expr, env, vargs...)
    loop_var = expr.args[1].args[1]
    lb, ub = expr.args[1].args[2].args
    body = expr.args[2]
    lb, ub = eval(lb, env), eval(ub, env)
    for i in lb:ub
        for ex in body.args
            if Meta.isexpr(ex, [:(=), :(~)])
                assignment!(pass, ex, merge(env, Dict(loop_var => i)), vargs...)
            elseif Meta.isexpr(ex, :for)
                for_loop!(pass, ex, merge(env, Dict(loop_var => i)), vargs...)
            else
                error()
            end
        end
    end
end

function assignment!(::CompilerPass, expr::Expr, env::Dict, vargs...) end

function post_process(::CompilerPass) end
