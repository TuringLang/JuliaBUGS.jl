"""
    _eval(m::Module, expr, env)
    _eval(expr, env)

Evaluates an expression within the given module and environment. If no module is provided, 
the function defaults to the JuliaBUGS module.

# Arguments
- `m::Module`: The module in which the expression is evaluated. Defaults to JuliaBUGS if not provided.
- `expr`: The expression to be evaluated. Can be of type `Number`, `Symbol`, or `Expr`.
- `env`: The environment in which the expression is evaluated.

# Returns
- The evaluated expression.
"""
function _eval(::Module, expr::Number, env)
    return expr
end

function _eval(::Module, expr::Symbol, env)
    if expr == :nothing
        return nothing
    elseif expr == :(:)
        return Colon()
    else # intentional strict, all corner cases should be handled above
        return env[expr]
    end
end

function _eval(m::Module, expr::Expr, env)
    if Meta.isexpr(expr, :call)
        f = expr.args[1]
        args = [_eval(m, arg, env) for arg in expr.args[2:end]]
        if f isa Expr # `JuliaBUGS.some_function` like
            # f = f.args[2].value
            error("Internal bugs: $f should not start with JuliaBUGS.")
        end
        return getfield(m, f)(args...)
    elseif Meta.isexpr(expr, :ref)
        array = _eval(m, expr.args[1], env)
        indices = [_eval(m, arg, env) for arg in expr.args[2:end]]
        return array[indices...]
    elseif Meta.isexpr(expr, :block)
        return _eval(m, expr.args[end], env)
    else
        error("Unknown expression type: $expr")
    end
end

function _eval(expr, env)
    return _eval(JuliaBUGS, expr, env)
end

# Resolves: setindex!!([1 2; 3 4], [2 3; 4 5], 1:2, 1:2) # returns 2×2 Matrix{Any}
# Alternatively, can overload BangBang.possible(
#     ::typeof(BangBang._setindex!), ::C, ::T, ::Vararg
# )
# to allow mutation, but the current solution seems create less possible problems, albeit less efficient.
function BangBang.NoBang._setindex(xs::AbstractArray, v::AbstractArray, I...)
    T = promote_type(eltype(xs), eltype(v))
    ys = similar(xs, T)
    if eltype(xs) !== Union{}
        copy!(ys, xs)
    end
    ys[I...] = v
    return ys
end
