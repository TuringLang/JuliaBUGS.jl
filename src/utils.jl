"""
    merge_collections(c1::Union{Dict, NamedTuple}, c2::Union{Dict, NamedTuple}, output_NamedTuple::Bool=true) -> Union{Dict, NamedTuple}

Merge two collections, `c1` and `c2`, which can be either dictionaries or named tuples, into a single collection 
(dictionary or named tuple). The function assumes that the values in the input collections are either `Number` or 
`Array` with matching sizes. If a key exists in both `c1` and `c2`, the merged collection will contain the non-missing 
values from `c1` and `c2`. If a key exists only in one of the collections, the resulting collection will contain the 
key-value pair from the respective collection.

# Arguments
- `c1::Union{Dict, NamedTuple}`: The first collection to merge.
- `c2::Union{Dict, NamedTuple}`: The second collection to merge.
- `output_NamedTuple::Bool=true`: Determines the type of the output collection. If true, the function outputs a NamedTuple. If false, it outputs a Dict.

# Returns
- `merged::Union{Dict, NamedTuple}`: A new collection containing the merged key-value pairs from `c1` and `c2`.

# Example
```jldoctest
julia> d1 = Dict(:a => [1, 2, missing], :b => 42);

julia> d2 = Dict(:a => [missing, 2, 4], :c => -1);

julia> d3 = Dict(:a => [missing, 3, 4], :c => -1); # value collision

julia> merge_collections(d1, d2, false)
Dict{Symbol, Any} with 3 entries:
  :a => [1, 2, 4]
  :b => 42
  :c => -1

julia> merge_collections(d1, d3, false)
ERROR: The arrays in key 'a' have different non-missing values at the same positions.
[...]
```
"""
function merge_collections(d1, d2, output_NamedTuple=true)
    merged_dict = Dict{Symbol,Any}()

    for key in Base.union(keys(d1), keys(d2))
        in_both_dicts = haskey(d1, key) && haskey(d2, key)
        values_match_type =
            in_both_dicts && (
                (
                    isa(d1[key], Array) &&
                    isa(d2[key], Array) &&
                    size(d1[key]) == size(d2[key])
                ) || (isa(d1[key], Number) && isa(d2[key], Number) && d1[key] == d2[key])
            )

        if values_match_type
            if isa(d1[key], Array)
                # Check if any position has different non-missing values in the two arrays.
                if !all(
                    i -> (
                        ismissing(d1[key][i]) ||
                        ismissing(d2[key][i]) ||
                        d1[key][i] == d2[key][i]
                    ),
                    1:length(d1[key]),
                )
                    error(
                        "The arrays in key '$(key)' have different non-missing values at the same positions.",
                    )
                end
                merged_value = coalesce.(d1[key], d2[key])
            else
                merged_value = d1[key]
            end

            merged_dict[key] = merged_value
        else
            merged_dict[key] = haskey(d1, key) ? d1[key] : d2[key]
        end
    end

    if output_NamedTuple
        return NamedTuple{Tuple(keys(merged_dict))}(values(merged_dict))
    else
        return merged_dict
    end
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
