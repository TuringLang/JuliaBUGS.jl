function extract_array_ndims(expr::Expr)
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
        else
            error("Unknown statement type: $stmt")
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
    variables = extract_variable_names(expr, loop_vars)
    for var in intersect(keys(variables), Ns)
        if variables[var] !== array_ndims[var]
            error("Variable $var has inconsistent dimensions")
        end
    end
    return merge(array_ndims, variables)
end

function extract_variables_used_in_bounds_and_indices(expr::Expr)
    return extract_variables_used_in_bounds_and_lhs_indices_block(expr, (), ())
end

function extract_variables_used_in_bounds_and_lhs_indices_block(
    expr::Expr, loop_vars::Tuple{Vararg{Symbol}}, variables::Tuple{Vararg{Symbol}}
)
    for stmt in expr.args
        if @capture(stmt, (lhs_ = rhs_) | (lhs_ ~ rhs_))
            variables = extract_variables_used_in_lhs_indices(lhs, loop_vars, variables)
        elseif @capture(
            stmt,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            variables = extract_variables_used_in_bounds_and_lhs_indices_block(
                body,
                (loop_vars..., loop_var),
                extract_variables_used_in_expr(
                    upper,
                    loop_vars,
                    extract_variables_used_in_expr(
                        lower, loop_vars, variables
                    ),
                ),
            )
        else
            error("Unknown statement type: $stmt")
        end
    end
    return variables
end

function extract_variables_used_in_expr(
    expr::Union{Int,Float64,Symbol,Expr},
    loop_vars::Tuple{Vararg{Symbol}},
    variables::Tuple{Vararg{Symbol}},
)::Tuple{Vararg{Symbol}}
    vars = extract_variable_names(expr, loop_vars)
    if vars === (;)
        return variables
    end
    return Tuple(union(variables, keys(vars)))
end

function extract_variables_used_in_lhs_indices(
    ::Symbol, ::Tuple{Vararg{Symbol}}, variables::Tuple{Vararg{Symbol}}
)
    return variables
end
function extract_variables_used_in_lhs_indices(
    expr::Union{Symbol,Expr},
    loop_vars::Tuple{Vararg{Symbol}},
    variables::Tuple{Vararg{Symbol}},
)
    if @capture(expr, v_[indices__])
        for index in indices
            variables = extract_variables_used_in_expr(index, loop_vars, variables)
        end
        return variables
    else
        variables = extract_variable_names(expr, loop_vars)
        return Tuple(union(variables, keys(vars)))
    end
end
