# why do we need to check for multiple assignments before computing transformed variables?
# because without checking, multiple expressions can assign to the same variable, and checking this before every `setindex!!` is inefficient

function check_multiple_assignments_pre_transform(state::CompileState)
    # assigning to the same array location or scalar variable more than once is generally not allowed
    # only exception is when the variable is a transformed variable

    # at this stage, we can check for multiple assignments intra-logical and intra-stochastic statements
    # this allows us to catch error faster and gives more assumptions to the `compute_transformed!` function

    # first check if there exist multiple assignments to scalar variables intra-logical and intra-stochastic statements
    for statement_collection in (state.logical_statements, state.stochastic_statements)
        for (i, statement) in enumerate(statement_collection)
            if !(statement.lhs isa Symbol)
                continue
            end
            for j in (i + 1):length(statement_collection)
                if !(statement_collection[j].lhs isa Symbol)
                    continue
                end
                if statement.lhs == statement_collection[j].lhs
                    throw(
                        ErrorException(
                            "$statement and $(statement_collection[j]) are both assigning to $(statement.lhs).",
                        ),
                    )
                end
            end
        end
    end

    # then check if there exist multiple assignments to same array location intra-logical and intra-stochastic statements
    for (statement_collection, definition_bitmap) in zip(
        (
            vcat(state.logical_statements, state.logical_for_statements),
            vcat(state.stochastic_statements, state.stochastic_for_statements),
        ),
        (state.logical_definition_bitmap, state.stochastic_definition_bitmap),
    )
        for statement in statement_collection
            if statement.lhs isa Symbol # scalar, no need to check
                continue
            end

            @capture(statement.lhs, lhs_var_[indices__])
            # initialize the bitmap if it doesn't exist
            if !haskey(definition_bitmap, lhs_var) && !haskey(state.data, lhs_var) ||
                (Missing <: eltype(state.data[lhs_var])) # `data` can contain missing arrays
                definition_bitmap[lhs_var] = falses(v...)
            end

            if lhs_var ∉ keys(definition_bitmap) # meaning lhs_var is a data variable that doesn't contain missing
                continue
            end

            if statement isa Statement
                check_multiple_assignments_inner!(state, statement.lhs, definition_bitmap)
            else
                for indices in Iterators.product(statement.bounds...)
                    check_multiple_assignments_inner!(
                        state,
                        statement.lhs,
                        definition_bitmap,
                        NamedTuple{statement.loop_vars}(Tuple(indices)),
                    )
                end
            end
        end
    end
end

function check_multiple_assignments_inner!(
    state, lhs, definition_bitmap, index_value_map=(;)
)
    simplified_lhs = simplify_lhs(merge(state.data, index_value_map), lhs)
    @capture(simplified_lhs, lhs_var_[indices__])
    if_defined = definition_bitmap[lhs_var][indices...]
    if any(if_defined .== true)
        all_indices = collect(Iterators.product(indices...))
        repeated_def_indices = all_indices[findall(if_defined)]
        throw(
            ErrorException(
                "Multiple assignments to variable $(lhs_var) at indices $(join(repeated_def_indices, ", ")) are not allowed.",
            ),
        )
    end
    return setindex!!(definition_bitmap[lhs_var], trues(length.(indices)...), indices...)
end

function check_multiple_assignments_post_transform(state::CompileState)
    # check scalar clashes
    for (l_stmt, s_stmt) in
        Iterators.product(state.logical_statements, state.stochastic_statements)
        if l_stmt.lhs isa Symbol &&
            s_stmt.lhs isa Symbol &&
            l_stmt.lhs == s_stmt.lhs &&
            l_stmt.lhs ∉ state.variables_tracked_in_eval_module
            throw(
                ErrorException(
                    "Both logical and stochastic statements are assigning to $(l_stmt.lhs)."
                ),
            )
        end
    end

    potential_clash_vars = intersect(
        keys(state.logical_definition_bitmap),
        keys(state.stochastic_definition_bitmap),
    ) # only care about variables that are defined in both logical and stochastic statements

    for var in potential_clash_vars
        if any(state.logical_definition_bitmap[var] .& state.stochastic_definition_bitmap[var])
            clash_indices = findall(state.logical_definition_bitmap[var] .& state.stochastic_definition_bitmap[var])
            arr = getfield(state.eval_module, var)
            if any(arr[clash_indices] .== missing)
                throw(
                    ErrorException(
                        "Both logical and stochastic statements are assigning to $(var) at indices $(join(clash_indices, ", ")).",
                    ),
                )
            end
        end
    end
end
