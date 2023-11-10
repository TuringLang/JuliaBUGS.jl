"""
    merge_collections(c1::NamedTuple, c2::NamedTuple) -> NamedTuple

Merge two NamedTuples, `c1` and `c2`, into a single NamedTuple. The function assumes that the values in the input 
NamedTuples are either `Number` or `Array` with matching sizes. If a key exists in both `c1` and `c2`, the merged 
NamedTuple will contain the non-missing values from `c1` and `c2`. If a key exists only in one of the NamedTuples, 
the resulting NamedTuple will contain the key-value pair from the respective NamedTuple.

# Arguments
- `c1::NamedTuple`: The first NamedTuple to merge.
- `c2::NamedTuple`: The second NamedTuple to merge.

# Returns
- `merged::NamedTuple`: A new NamedTuple containing the merged key-value pairs from `c1` and `c2`.

# Example
```jldoctest
julia> nt1 = (a = [1, 2, missing], b = 42);

julia> nt2 = (a = [missing, 2, 4], c = -1);

julia> nt3 = (a = [missing, 3, 4], c = -1); # value collision

julia> merge_collections(nt1, nt2)
(a = [1, 2, 4], b = 42, c = -1)

julia> merge_collections(nt1, nt3)
ERROR: The arrays in key 'a' have different non-missing values at the same positions.
[...]
```
"""
function merge_collections(c1::NamedTuple, c2::NamedTuple)::NamedTuple
    keys_union = union(keys(c1), keys(c2))
    merged = NamedTuple()

    for key in keys_union
        if haskey(c1, key) && haskey(c2, key)
            val1 = c1[key]
            val2 = c2[key]
            if isa(val1, Number) && isa(val2, Number)
                merged_value =
                    val1 == val2 ? val1 : error("The values for '$key' are different.")
            elseif isa(val1, AbstractArray) && isa(val2, AbstractArray)
                if size(val1) != size(val2)
                    error("The arrays for key '$key' have different sizes.")
                end
                merged_value = [
                    if ismissing(v1)
                        v2
                    elseif ismissing(v2)
                        v1
                    elseif v1 == v2
                        v1
                    else
                        error(
                            "The arrays in key '$key' have different non-missing values at the same positions.",
                        )
                    end for (v1, v2) in zip(val1, val2)
                ]
            else
                error(
                    "Values for key '$key' must be both numbers or both arrays with matching sizes.",
                )
            end
            merged = merge(merged, NamedTuple{(key,)}((merged_value,)))
        else
            merged_value = haskey(c1, key) ? c1[key] : c2[key]
            merged = merge(merged, NamedTuple{(key,)}((merged_value,)))
        end
    end

    return merged
end

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
function _eval(expr::AbstractRange, env)
    return expr
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

# defines some default bijectors for link functions
# these are currently not in use, because we transform the expression by calling inverse functions 
# on the RHS (in the case of logical assignment) or disallow the use of link functions (in the case of
# stochastic assignments)

struct LogisticBijector <: Bijectors.Bijector end

Bijectors.transform(::LogisticBijector, x::Real) = logistic(x)
Bijectors.transform(::Inverse{LogisticBijector}, x::Real) = logit(x)
Bijectors.logabsdet(::LogisticBijector, x::Real) = log(logistic(x)) + log(1 - logistic(x))

struct CExpExpBijector <: Bijectors.Bijector end

Bijectors.transform(::CExpExpBijector, x::Real) = icloglog(x)
Bijectors.transform(::Inverse{CExpExpBijector}, x::Real) = cloglog(x)
Bijectors.logabsdet(::CExpExpBijector, x::Real) = -log(cloglog(-x))

struct ExpBijector <: Bijectors.Bijector end

Bijectors.transform(::ExpBijector, x::Real) = exp(x)
Bijectors.transform(::Inverse{ExpBijector}, x::Real) = log(x)
Bijectors.logabsdet(::ExpBijector, x::Real) = x

struct PhiBijector <: Bijectors.Bijector end

Bijectors.transform(::PhiBijector, x::Real) = phi(x)
Bijectors.transform(::Inverse{PhiBijector}, x::Real) = probit(x)
Bijectors.logabsdet(::PhiBijector, x::Real) = -0.5 * (x^2 + log(2π))

link_function_to_bijector_mapping = Dict(
    :logit => LogisticBijector(),
    :cloglog => CExpExpBijector(),
    :log => ExpBijector(),
    :probit => PhiBijector(),
)
