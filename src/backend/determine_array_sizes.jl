function determine_array_sizes!(state::CompileState)
    for (k, v) in pairs(state.data) # size of data arrays are known, initializations is treated after compilation
        if v isa Array
            state.array_sizes[k] = size(v)
        end
    end

    for collection in (state.logical_statements, state.stochastic_statements)
        for statement in collection
            simplified_lhs = simplify_lhs(state.data, statement.lhs)
            if check_if_partially_specified_as_data(state.data, simplified_lhs)
                if is_logical(for_statement)
                    error(
                        "$(for_statement.lhs) is specified at data, thus can't be assigned to.",
                    )
                end
            end
            if simplified_lhs isa Symbol # scalar, no need to determine array sizes
                continue
            end
            determine_array_sizes_inner!(state, simplified_lhs)
        end
    end

    for collection in (state.logical_for_statements, state.stochastic_for_statements)
        for for_statement in collection
            for indices in Iterators.product(for_statement.bounds...)
                simplified_lhs = simplify_lhs(
                    merge(state.data, NamedTuple{for_statement.loop_vars}(Tuple(indices))),
                    for_statement.lhs,
                )
                if check_if_partially_specified_as_data(state.data, simplified_lhs)
                    if is_logical(for_statement)
                        error(
                            "$(for_statement.lhs) is specified at data, thus can't be assigned to.",
                        )
                    end
                end
                determine_array_sizes_inner!(state, simplified_lhs)
            end
        end
    end
end

function determine_array_sizes_inner!(state::CompileState, simplified_lhs::Expr)
    @capture(simplified_lhs, lhs_var_[indices__])
    if haskey(state.data, lhs_var)
        # check if the number of dimensions and sizes are consistent with data
        if length(last.(indices)) != length(state.array_sizes[lhs_var])
            @show length(last.(indices)) length(state.array_sizes[lhs_var])
            throw(
                ErrorException(
                    "$(simplified_lhs)'s number of dimensions doesn't match the data."
                ),
            )
        elseif !all(last.(indices) .<= state.array_sizes[lhs_var])
            throw(ErrorException("$(simplified_lhs)'s indices are out of bounds."))
        end
        return nothing
    end
    state.array_sizes[lhs_var] =
        max.(get!(state.array_sizes, lhs_var, [last(indices[1])]), last.(indices))
    return nothing
end

function check_if_partially_specified_as_data(
    value_map::NamedTuple{names,Ts}, simplified_lhs
) where {names,Ts}
    if simplified_lhs isa Symbol
        return simplified_lhs in names
    else
        @capture(simplified_lhs, var_[indices__])
        if var ∉ names # if not captured successfully, this will error because `var` is not defined
            return false
        else
            if eltype(value_map[var]) <: Real
                return true
            else
                @assert eltype(value_map[var]) <: Union{Missing,<:Real}
                values = view(value_map[var], indices...)
                # all the values must be all or none missing
                T = typeof(values[1])
                if !all(Base.Fix2(isa, T), values)
                    error(
                        "$(simplified_lhs) is partially specified at data, thus can't be assigned to.",
                    )
                end
                return T != Missing
            end
        end
    end
end

function concretize_colon_indexing!(state::CompileState)
    for collection in (
        state.logical_statements,
        state.stochastic_statements,
        state.logical_for_statements,
        state.stochastic_for_statements,
    )
    for (i, statement) in enumerate(collection)
        new_rhs = MacroTools.postwalk(statement.rhs) do sub_expr
                if MacroTools.@capture(sub_expr, v_[indices__])
                    return :($(v)[$(
                        [
                            idx == :(:) ? :(1:($(state.array_sizes[v][i]))) : idx for
                            (i, idx) in enumerate(indices)
                        ]...
                    )])
                end
                sub_expr
            end
        T = typeof(statement)
        if T <: Statement
            collection[i] = T(statement.rhs_vars, statement.rhs_funs, statement.lhs, new_rhs)
        else
            collection[i] = T(
                statement.loop_vars,
                statement.rhs_vars,
                statement.rhs_funs,
                statement.bounds,
                statement.lhs,
                new_rhs,
            )
        end
    end
    end
end
