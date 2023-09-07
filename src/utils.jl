"""
    _eval(expr, env)

`_eval` mimics `Base.eval`, but uses precompiled functions. This is possible because the expressions we want to 
evaluate only have two kinds of expressions: function calls and indexing.
`env` is a data structure mapping symbols in `expr` to values, values can be arrays or scalars.
"""
function _eval(expr::Number, env)
    return expr
end
function _eval(expr::Symbol, env)
    if expr == :nothing
        return nothing
    elseif expr == :(:)
        return Colon()
    else # intentional strict, all corner cases should be handled above
        return env[expr]
    end
end
function _eval(expr::Expr, env)
    if Meta.isexpr(expr, :call)
        f = expr.args[1]
        args = [_eval(arg, env) for arg in expr.args[2:end]]
        if f isa Expr # `JuliaBUGS.some_function` like
            f = f.args[2].value
        end
        return getfield(JuliaBUGS, f)(args...) # assume all functions used are available under `JuliaBUGS`
    elseif Meta.isexpr(expr, :ref)
        array = _eval(expr.args[1], env)
        indices = [_eval(arg, env) for arg in expr.args[2:end]]
        return array[indices...]
    elseif Meta.isexpr(expr, :block)
        return _eval(expr.args[end], env)
    else
        error("Unknown expression type: $expr")
    end
end
function _eval(expr, env)
    return error("Unknown expression type: $expr of type $(typeof(expr))")
end

"""
    evaluate(vn::VarName, env)

Retrieve the value of a possible variable identified by `vn` from `env`, return `nothing` if not found.
"""
function evaluate(vn::VarName, env)
    sym = getsym(vn)
    ret = nothing
    try
        ret = get(env[sym], getlens(vn))
    catch _
    end
    return ismissing(ret) ? nothing : ret
end

"""
    _length(vn::VarName)

Return the length of a possible variable identified by `vn`.
Only valid if `vn` is:
    - a scalar
    - an array indexing whose indices are concrete(no `start`, `end`, `:`)

! Should not be used outside of the usage demonstrated in this file.

"""
function _length(vn::VarName)
    getlens(vn) isa Setfield.IdentityLens && return 1
    return prod([length(index_range) for index_range in getlens(vn).indices])
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