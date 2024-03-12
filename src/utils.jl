"""
    decompose_for_expr(expr::Expr)

Decompose a for-loop expression into its components. The function returns four items: the 
loop variable, the lower bound, the upper bound, and the body of the loop.
"""
@inline function decompose_for_expr(expr::Expr)
    loop_var::Symbol = expr.args[1].args[1]
    lb::Union{Int,Float64,Symbol,Expr} = expr.args[1].args[2].args[2]
    ub::Union{Int,Float64,Symbol,Expr} = expr.args[1].args[2].args[3]
    body::Expr = expr.args[2]
    return loop_var, lb, ub, body
end

"""
    extract_variable_names_and_numdims(expr, excluded)

Extract all the array variable names and number of dimensions from a given simple expression. 

# Examples:
```jldoctest
julia> extract_variable_names_and_numdims(:((a + b) * c), ())
(a = 0, b = 0, c = 0)

julia> extract_variable_names_and_numdims(:((a + b) * c), (:a,))
(b = 0, c = 0)

julia> extract_variable_names_and_numdims(:(a[i]), ())
(a = 1, i = 0)

julia> extract_variable_names_and_numdims(:(a[i]), (:i,))
(a = 1,)

julia> extract_variable_names_and_numdims(42, ())
NamedTuple()

julia> extract_variable_names_and_numdims(:x, (:x,))
NamedTuple()

julia> extract_variable_names_and_numdims(:(x[1, :]), ())
(x = 2,)
```
"""
function extract_variable_names_and_numdims(::Union{Int,Float64}, ::Tuple{Vararg{Symbol}})
    return (;)
end
function extract_variable_names_and_numdims(expr::Symbol, excluded::Tuple{Vararg{Symbol}})
    return if expr in excluded || expr in (:missing, :nothing)
        (;)
    else
        NamedTuple{(expr,)}((0,))
    end
end
function extract_variable_names_and_numdims(expr::Expr, excluded::Tuple{Vararg{Symbol}})
    variables = Dict{Symbol,Int}()
    MacroTools.prewalk(expr) do sub_expr
        if !(sub_expr isa Expr)
            return sub_expr
        end
        if @capture(sub_expr, f_(args__))
            for arg in args
                if arg isa Symbol && !(arg in excluded)
                    variables[arg] = 0
                end
            end
        elseif @capture(sub_expr, v_[idxs__])
            variables[v] = length(idxs)
            for idx in idxs
                if idx isa Symbol && idx !== :(:) && !(idx in excluded)
                    variables[idx] = 0
                end
            end
        end
        return sub_expr
    end
    return NamedTuple(variables)
end

"""
    extract_variable_names_and_numdims(expr::Expr)
   
Extract all the array variable names and number of dimensions. Inconsistent number of dimensions
will raise an error.

# Example:
```jldoctest
extract_variable_names_and_numdims(
    @bugs begin
        for i in 1:N
            for j in 1:T
                Y[i, j] = _step((var"obs.t"[i] - t[j]) + eps)
                dN[i, j] = Y[i, j] * _step((t[j + 1] - var"obs.t"[i]) - eps) * fail[i]
            end
        end
        for j in 1:T
            for i in 1:N
                dN[i, j] ~ dpois(Idt[i, j])
                Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]
            end
            dL0[j] ~ dgamma(mu[j], c)
            mu[j] = var"dL0.star"[j] * c
            var"S.treat"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * -0.5))
            var"S.placebo"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * 0.5))
        end
        c = 0.001
        r = 0.1
        for j in 1:T
            var"dL0.star"[j] = r * (t[j + 1] - t[j])
        end
        beta ~ dnorm(0.0, 1.0e-6)
    end
)

# output

(N = 0, T = 0, Y = 2, var"obs.t" = 1, eps = 0, t = 1, dN = 2, fail = 1, Idt = 2, Z = 1, beta = 0, dL0 = 1, mu = 1, c = 0, var"dL0.star" = 1, var"S.treat" = 1, var"S.placebo" = 1, r = 0)
```
"""
function extract_variable_names_and_numdims(expr::Expr)
    return extract_array_ndims_block(expr, (), NamedTuple())
end

function extract_array_ndims_block(
    expr::Expr, loop_vars::Tuple{Vararg{Symbol}}, array_ndims::NamedTuple{Ns,Ts}
) where {Ns,Ts}
    for stmt in expr.args
        if @capture(stmt, (lhs_ = rhs_) | (lhs_ ~ rhs_))
            array_ndims = extract_array_ndims_expr(
                rhs, loop_vars, extract_array_ndims_expr(lhs, loop_vars, array_ndims)
            )
        elseif @capture(
            stmt,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            array_ndims = extract_array_ndims_block(
                body,
                (loop_vars..., loop_var),
                extract_array_ndims_expr(
                    upper,
                    loop_vars,
                    extract_array_ndims_expr(lower, loop_vars, array_ndims),
                ),
            )
        end
    end
    return array_ndims
end

function extract_array_ndims_expr(
    ::Union{Int,Float64}, ::Tuple{Vararg{Symbol}}, array_dims::NamedTuple
)
    return array_dims
end
function extract_array_ndims_expr(
    expr::Union{Symbol,Expr},
    loop_vars::Tuple{Vararg{Symbol}},
    array_ndims::NamedTuple{Ns,Ts},
) where {Ns,Ts}
    variables = extract_variable_names_and_numdims(expr, loop_vars)
    for var in intersect(keys(variables), Ns)
        if variables[var] !== array_ndims[var]
            error("Variable $var has inconsistent dimensions")
        end
    end
    return merge(array_ndims, variables)
end

"""
    extract_variables_in_bounds_and_lhs_indices(expr::Expr)

Extract all the variable names used in the bounds and indices of the arrays in the program.

# Example:
```jldoctest
JuliaBUGS.extract_variables_in_bounds_and_lhs_indices(
    @bugs begin
        for i in 1:N
            for j in 1:T
                Y[i, j] = _step((var"obs.t"[i] - t[j]) + eps)
                dN[i, j] = Y[i, j] * _step((t[j + 1] - var"obs.t"[i]) - eps) * fail[i]
            end
        end
        for j in 1:T
            for i in 1:N
                dN[i, j] ~ dpois(Idt[i, j])
                Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]
            end
            dL0[j] ~ dgamma(mu[j], c)
            mu[j] = var"dL0.star"[j] * c
            var"S.treat"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * -0.5))
            var"S.placebo"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * 0.5))
        end
        c = 0.001
        r = 0.1
        for j in 1:T
            var"dL0.star"[j] = r * (t[j + 1] - t[j])
        end
        beta ~ dnorm(0.0, 1.0e-6)
    end
)

# output

(:N, :T)
```
"""
function extract_variables_in_bounds_and_lhs_indices(expr::Expr)
    return extract_variables_in_bounds_and_lhs_indices(expr, (), ())
end
function extract_variables_in_bounds_and_lhs_indices(
    expr::Expr, loop_vars::Tuple{Vararg{Symbol}}, variables::Tuple{Vararg{Symbol}}
)
    for stmt in expr.args
        if @capture(stmt, (lhs_ = rhs_) | (lhs_ ~ rhs_))
            if @capture(lhs, v_[indices__])
                for index in indices
                    variables = extract_variables_used_in_expr(index, loop_vars, variables)
                end
            end
        elseif @capture(
            stmt,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            variables = extract_variables_in_bounds_and_lhs_indices(
                body,
                (loop_vars..., loop_var),
                extract_variables_used_in_expr(
                    upper,
                    loop_vars,
                    extract_variables_used_in_expr(lower, loop_vars, variables),
                ),
            )
        end
    end
    return variables
end

function extract_variables_used_in_expr(
    expr::Union{Int,Float64,Symbol,Expr},
    loop_vars::Tuple{Vararg{Symbol}},
    variables::Tuple{Vararg{Symbol}},
)::Tuple{Vararg{Symbol}}
    vars = extract_variable_names_and_numdims(expr, loop_vars)
    if vars === (;)
        return variables
    end
    return Tuple(union(variables, keys(vars)))
end

function simplify_lhs(::NamedTuple, lhs::Symbol)
    return lhs
end
function simplify_lhs(data::NamedTuple, lhs::Expr)
    if Meta.isexpr(lhs, :ref)
        var = lhs.args[1]
        indices = lhs.args[2:end]
        for i in eachindex(indices)
            indices[i] = simple_arithmetic_eval(data, indices[i])
        end
        return (var, indices...)
    else
        error(
            "LHS of a statement can only be a symbol or an indexing expression, but get $lhs.",
        )
    end
end

"""
    extract_variables_assigned_to(expr::Expr)

Extract all the variables assigned to in the program.

# Example:
```jldoctest
JuliaBUGS.extract_variables_assigned_to(
    @bugs begin
        for i in 1:N
            for j in 1:T
                Y[i, j] = _step((var"obs.t"[i] - t[j]) + eps)
                dN[i, j] = Y[i, j] * _step((t[j + 1] - var"obs.t"[i]) - eps) * fail[i]
            end
        end
        for j in 1:T
            for i in 1:N
                dN[i, j] ~ dpois(Idt[i, j])
                Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]
            end
            dL0[j] ~ dgamma(mu[j], c)
            mu[j] = var"dL0.star"[j] * c
            var"S.treat"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * -0.5))
            var"S.placebo"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * 0.5))
        end
        c = 0.001
        r = 0.1
        for j in 1:T
            var"dL0.star"[j] = r * (t[j + 1] - t[j])
        end
        beta ~ dnorm(0.0, 1.0e-6)
    end
)

# output

((:c, :r), (:beta,), (Symbol("dL0.star"), :dN, :mu, Symbol("S.treat"), Symbol("S.placebo"), :Y, :Idt), (:dN, :dL0))
```
"""
function extract_variables_assigned_to(expr::Expr)
    return Tuple.(
        extract_variables_assigned_to(
            expr, Symbol[], Symbol[], Set{Symbol}(), Set{Symbol}()
        )
    )
end
function extract_variables_assigned_to(
    expr::Expr,
    logical_scalars::Vector{Symbol},
    stochastic_scalars::Vector{Symbol},
    logical_arrays::Set{Symbol},
    stochastic_arrays::Set{Symbol},
)
    for stmt in expr.args
        if @capture(stmt, (lhs_ = rhs_))
            if lhs isa Symbol
                if lhs in logical_scalars
                    error("Logical scalar variable $lhs is assigned to more than once")
                end
                push!(logical_scalars, lhs)
            else
                push!(logical_arrays, lhs.args[1])
            end
        elseif @capture(stmt, (lhs_ ~ rhs_))
            if lhs isa Symbol
                if lhs in stochastic_scalars
                    error("Stochastic scalar variable $lhs is assigned to more than once")
                end
                push!(stochastic_scalars, lhs)
            else
                push!(stochastic_arrays, lhs.args[1])
            end
        elseif @capture(
            stmt,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            extract_variables_assigned_to(
                body, logical_scalars, stochastic_scalars, logical_arrays, stochastic_arrays
            )
        end
    end
    return logical_scalars, stochastic_scalars, logical_arrays, stochastic_arrays
end

"""
    simple_arithmetic_eval(data, expr)

This function evaluates expressions that consist solely of arithmetic operations and indexing. It 
is specifically designed for scenarios such as calculating array indices or determining loop boundaries.

# Example:
```jldoctest
julia> simple_arithmetic_eval((a = 1, b = [1, 2]), 1)
1

julia> simple_arithmetic_eval((a = 1, b = [1, 2]), :a)
1

julia> simple_arithmetic_eval((a = 1, b = [1, 2]), :(a + b[1]))
2
```
"""
function simple_arithmetic_eval(data::NamedTuple, expr::Union{Int,UnitRange{Int}})
    return expr
end
function simple_arithmetic_eval(data::NamedTuple{names,Ts}, expr::Symbol) where {names,Ts}
    if expr ∉ names
        throw(ArgumentError("Don't know the value of $expr."))
    end
    return Int(data[expr])
end
function simple_arithmetic_eval(data::NamedTuple, expr::Expr)
    if Meta.isexpr(expr, :call)
        f, args... = expr.args
        for i in eachindex(args)
            value = simple_arithmetic_eval(data, args[i])
            if value isa UnitRange
                error("Don't know how to do arithmetic between UnitRange and Integer.")
            else
                args[i] = Int(value)
            end
        end
        if f == :+
            return sum(args)
        elseif f == :*
            return prod(args)
        else
            @assert length(args) == 2
            if f == :-
                return args[1] - args[2]
            elseif f == :/
                return Int(args[1] / args[2])
            elseif f == :(:)
                return UnitRange(Int(args[1]), Int(args[2]))
            else
                error("Don't know how to evaluate function $(string(f)).")
            end
        end
    elseif Meta.isexpr(expr, :ref)
        var, indices... = expr.args
        for i in eachindex(indices)
            indices[i] = simple_arithmetic_eval(data, indices[i])
        end
        return Int(data[var][indices...])
    else
        error("Don't know how to evaluate $expr.")
    end
end

"""
    _eval(expr, env, dist_store)

`_eval` mimics `Base.eval`, but uses precompiled functions. This is possible because the expressions we want to 
evaluate only have two kinds of expressions: function calls and indexing.
`env` is a data structure mapping symbols in `expr` to values, values can be arrays or scalars.
"""
function _eval(expr::Number, env, dist_store)
    return expr
end
function _eval(expr::Symbol, env, dist_store)
    if expr == :nothing
        return nothing
    elseif expr == :(:)
        return Colon()
    else # intentional strict, all corner cases should be handled above
        return env[expr]
    end
end
function _eval(expr::AbstractRange, env, dist_store)
    return expr
end
function _eval(expr::Expr, env, dist_store)
    if Meta.isexpr(expr, :call)
        f = expr.args[1]
        if f === :cumulative || f === :density
            if length(expr.args) != 3
                error(
                    "density function should have 3 arguments, but get $(length(expr.args)).",
                )
            end
            rv1, rv2 = expr.args[2:3]
            dist = if Meta.isexpr(rv1, :ref)
                var, indices... = rv1.args
                for i in eachindex(indices)
                    indices[i] = _eval(indices[i], env, dist_store)
                end
                vn = AbstractPPL.VarName{var}(
                    AbstractPPL.Setfield.IndexLens(Tuple(indices))
                )
                dist_store[vn]
            elseif rv1 isa Symbol
                vn = AbstractPPL.VarName{rv1}()
                dist_store[vn]
            else
                error(
                    "the first argument of density function should be a variable, but got $(rv1).",
                )
            end
            rv2 = _eval(rv2, env, dist_store)
            if f === :cumulative
                return cdf(dist, rv2)
            else
                return pdf(dist, rv2)
            end
        else
            args = [_eval(arg, env, dist_store) for arg in expr.args[2:end]]
            if f isa Expr # `JuliaBUGS.some_function` like
                f = f.args[2].value
            end
            return getfield(JuliaBUGS, f)(args...) # assume all functions used are available under `JuliaBUGS`
        end
    elseif Meta.isexpr(expr, :ref)
        array = _eval(expr.args[1], env, dist_store)
        indices = [_eval(arg, env, dist_store) for arg in expr.args[2:end]]
        return array[indices...]
    elseif Meta.isexpr(expr, :block)
        return _eval(expr.args[end], env, dist_store)
    else
        error("Unknown expression type: $expr")
    end
end
function _eval(expr, env, dist_store)
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
