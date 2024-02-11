struct DetermineArraySizesState
    data::NamedTuple
    array_sizes::ComponentArray{Int}
end

function DetermineArraySizesState(
    ::Statements{rhs_array_vars}, data::NamedTuple{names,Ts}
) where {rhs_array_vars, names, Ts}
    _names = setdiff(map(first, rhs_array_vars), names)
    n_dims = [last(v) for v in rhs_array_vars if first(v) in _names]
    init_array_sizes = [fill(1, n_dim) for n_dim in n_dims]
    array_sizes = ComponentArray{Int}(NamedTuple{Tuple(_names)}(init_array_sizes))
    return DetermineArraySizesState(data, array_sizes)
end

function determine_array_sizes(stmts::Statements, data::NamedTuple{names,Ts}) where {names,Ts}
    state = DetermineArraySizesState(stmts, data)
    for collection in (stmts.logical_statements, stmts.stochastic_statements)
        for statement in collection
            simplified_lhs = statement.lhs
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

    for collection in
        (stmts.logical_for_statements, stmts.stochastic_for_statements)
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

    data_array_vars = filter(k -> ndims(data[k]) > 0, keys(data))
    data_array_sizes = NamedTuple{Tuple(data_array_vars)}(
        map(x -> size(data[x]), data_array_vars)
    )

    return merge(NamedTuple(state.array_sizes), data_array_sizes)
end

function determine_array_sizes_inner!(state::DetermineArraySizesState, simplified_lhs::Expr)
    @capture(simplified_lhs, lhs_var_[indices__])
    max_indices = map(x -> x isa UnitRange ? last(x) : x, indices)
    if haskey(state.data, lhs_var)
        if !all(max_indices .<= state.array_sizes[lhs_var])
            throw(ErrorException("$(simplified_lhs)'s indices are out of bounds."))
        end
        return nothing
    end
    state.array_sizes[lhs_var] = max.(state.array_sizes[lhs_var], max_indices)
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

function concretize_colon_indexing!(stmts::Statements, array_sizes::NamedTuple)
    for collection in (
        stmts.logical_statements,
        stmts.stochastic_statements,
        stmts.logical_for_statements,
        stmts.stochastic_for_statements,
    )
        for (i, statement) in enumerate(collection)
            new_rhs = MacroTools.postwalk(statement.rhs) do sub_expr
                if MacroTools.@capture(sub_expr, v_[indices__])
                    return :($(v)[$(
                        [
                            idx == :(:) ? :(1:($(array_sizes[v][i]))) : idx for
                            (i, idx) in enumerate(indices)
                        ]...
                    )])
                end
                sub_expr
            end
            T = typeof(statement)
            if T <: Statement
                collection[i] = T(
                    statement.rhs_vars, statement.rhs_functions_used, statement.lhs, new_rhs
                )
            else
                collection[i] = T(
                    statement.loop_vars,
                    statement.rhs_vars,
                    statement.rhs_functions_used,
                    statement.bounds,
                    statement.lhs,
                    new_rhs,
                )
            end
        end
    end
end
