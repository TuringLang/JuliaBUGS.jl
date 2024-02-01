
function check_multiple_assignments(state::CompileState)
    # check repeated assignment to scalar variables across all pairs of statements
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

    for statement_collection in (
        vcat(state.logical_statements, state.logical_for_statements),
        vcat(state.stochastic_statements, state.stochastic_for_statements),
    )
        definition_map = Dict()
        for (k, v) in state.array_sizes
            if k ∉ keys(state.data)
                definition_map[k] = falses(v...)
            end
        end

        for statement in statement_collection
            if statement.lhs isa Symbol
                continue
            end

            if statement.lhs.args[1] ∉ keys(definition_map)
                continue
            end

            if statement isa Statement
                check_multiple_assignments_inner!(state, statement.lhs, definition_map)
            else
                for indices in Iterators.product(statement.bounds...)
                    check_multiple_assignments_inner!(
                        state,
                        plug_in_loopvar(statement, Val(:lhs), indices),
                        definition_map,
                    )
                end
            end
        end
    end

    # cases where a logical statement and a stochastic statement assign to the same array location is not checked
    # because it might be a valid case when the variable under inspection is a transformed variable
    # this check will be done after `compute_transformed!`
end

function check_multiple_assignments_inner(state, lhs, definition_map)
    simplified_lhs = simplify_lhs(state.data, lhs)
    @capture(simplified_lhs, lhs_var_[indices__])
    if_defined = definition_map[lhs_var][indices...]
    if any(if_defined .== true)
        @show indices if_defined
        all_indices = collect(Iterators.product(indices...))
        repeated_def_indices = all_indices[findall(if_defined)]
        throw(
            ErrorException(
                "Multiple assignments to variable $(lhs_var) at indices $(join(repeated_def_indices, ", ")) are not allowed.",
            ),
        )
    end
    return setindex!!(definition_map[lhs_var], trues(length.(indices)...), indices...)
end
