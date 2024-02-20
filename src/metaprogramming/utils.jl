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
                if idx isa Symbol && !(idx in excluded)
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
   
Extract all the array variable names and number of dimensions.

# Example:
```jldoctest
julia> extract_variable_names_and_numdims(BUGSExamples.leuk.model_def)
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
    extract_variable_names(expr::Expr)

Extract all the variable names used in the program.
# Example:
```jldoctest
julia> extract_variable_names(BUGSExamples.leuk.model_def)
(:N, :T, :Y, Symbol("obs.t"), :eps, :t, :dN, :fail, :Idt, :Z, :beta, :dL0, :mu, :c, Symbol("dL0.star"), Symbol("S.treat"), Symbol("S.placebo"), :r)
```
"""
function extract_variable_names(expr::Expr)
    return Tuple(keys(extract_variable_names_and_numdims(expr)))
end

"""
    extract_variables_in_bounds_and_lhs_indices(expr::Expr)

Extract all the variable names used in the bounds and indices of the arrays in the program.

# Example:
```jldoctest
julia> JuliaBUGS.extract_variables_in_bounds_and_lhs_indices(BUGSExamples.leuk.model_def)
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

"""
    extract_variables_assigned_to(expr::Expr)

Extract all the variables assigned to in the program.

# Example:
```jldoctest
julia> JuliaBUGS.extract_variables_assigned_to(BUGSExamples.leuk.model_def)
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
    extract_statement_loop_bounds(model_def::Expr)

Extract the loop bounds for each statement in the program. If a variable is not in a loop, return an empty tuple.
"""
function extract_statement_loop_bounds(model_def::Expr)
    return extract_statement_loop_bounds!(model_def, (), Tuple{Vararg{Expr}}[])
end
function extract_statement_loop_bounds!(
    model_def::Expr,
    loop_bounds::Tuple{Vararg{Expr}},
    stmt_loop_bounds::Vector{Tuple{Vararg{Expr}}},
)
    for statement in model_def.args
        if @capture(statement, (lhs_ = rhs_) | (lhs_ ~ rhs_))
            push!(stmt_loop_bounds, loop_bounds)
        elseif @capture(
            statement,
            for loop_var_ in loop_bound_
                body_
            end
        )
            extract_statement_loop_bounds!(
                body, (loop_bounds..., loop_bound), stmt_loop_bounds
            )
        end
    end
    return stmt_loop_bounds
end
