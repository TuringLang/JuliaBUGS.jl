function is_special_case(state::CompileState)
    return all(all_for_statements(state)) do stmt
        expr = stmt.lhs
        loop_vars = stmt.loop_vars
        @capture(expr, v_[indices__])
        stmtid_to_loopvar_map = Dict()
        for (i, idx) in enumerate(indices)
            if idx isa Symbol
                stmtid_to_loopvar_map[i] = idx
            elseif @capture(idx, a_ + b_Int) || @capture(idx, a_ - b_Int)
                stmtid_to_loopvar_map[i] = a
            else
                return false
            end
        end

        unused_loop_vars = setdiff(loop_vars, values(stmtid_to_loopvar_map))
        if !isempty(unused_loop_vars)
            error(
                "Loop variables $unused_loop_vars are not used, which means some expressions will be repeated.",
            )
        end

        return true
    end
end

function range_covered(for_statement::ForStatement)
    
end

function determine_array_sizes_easy!(state::CompileState)
    ranges_map = Dict()
    for statement in non_for_statements(state)
        if statement.lhs isa Symbol
            ranges_map[statement] = nothing
        else
            @capture(statement.lhs, v_[indices__])
            ranges_map[v] = indices
        end
    end

    for for_statement in all_for_statements(state)
        @capture(for_statement.lhs, v_[indices__])
        local_range_map = NamedTuple{for_statement.loop_vars}(for_statement.bounds)
        ranges = Any[]
        for idx in indices
            if idx isa Symbol # e.g. `i`
                push!(ranges, local_range_map[idx])
            elseif @capture(idx, a_ + b_Int) # e.g. `i + 1`, `ForStatement` constructor will make sure the first argument of `+` will be the loop_var
                push!(ranges, (local_range_map[a].start + b, local_range_map[a].stop + b))
            elseif @capture(idx, a_ - b_Int) # e.g. `i - 1`, not `1 - i` (decreasing not allowed)
                push!(ranges, (local_range_map[a].start - b, local_range_map[a].stop - b))
            end
        end
        ranges_map[for_statement.lhs] = ranges
    end

    # TODO: ...

end
