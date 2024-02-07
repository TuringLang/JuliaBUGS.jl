struct CompileState
    data # the original data, used for reconstructing

    eval_module::Module
    variables_tracked_in_eval_module::Set{Symbol} # data variables and transformed variables

    logical_statements::Vector{Statement{:(=)}}
    stochastic_statements::Vector{Statement{:(~)}}
    logical_for_statements::Vector{ForStatement{:(=)}}
    stochastic_for_statements::Vector{ForStatement{:(~)}}

    # logical statements that are fully evaluated for transformed variables
    excluded_logical_statements
    excluded_logical_for_statements

    array_sizes

    # used for check repeated assignments
    logical_definition_bitmap
    stochastic_definition_bitmap
end

function CompileState(expr::Expr, data)
    logical_statements = Statement{:(=)}[]
    stochastic_statements = Statement{:(~)}[]
    logical_for_statements = ForStatement{:(=)}[]
    stochastic_for_statements = ForStatement{:(~)}[]

    assignments = filter(expr.args) do arg
        !Meta.isexpr(arg, :for)
    end
    for assignment in assignments
        statement = Statement(assignment, data)
        if is_logical(statement)
            push!(logical_statements, statement)
        else
            push!(stochastic_statements, statement)
        end
    end

    for loop in loop_fission(expr.args)
        for_statement = ForStatement(loop, data)
        if is_logical(for_statement)
            push!(logical_for_statements, for_statement)
        else
            push!(stochastic_for_statements, for_statement)
        end
    end

    return CompileState(
        data,
        create_eval_module(data),
        Set(keys(data)),
        logical_statements,
        stochastic_statements,
        logical_for_statements,
        stochastic_for_statements,
        Set(),
        Set(),
        Dict(),
        Dict(),
        Dict(),
    )
end

function get_data_and_transformed_variables(state::CompileState)
    t = Tuple(state.variables_tracked_in_eval_module)
    return NamedTuple{t}(
        map(t) do var
            getproperty(state.eval_module, var)
        end,
    )
end

# some iterators
function all_statements(state::CompileState)
    return Iterators.flatten((
        state.logical_statements,
        state.stochastic_statements,
        state.logical_for_statements,
        state.stochastic_for_statements,
    ),)
end
function all_logical_statements(state::CompileState)
    return Iterators.flatten((state.logical_statements, state.logical_for_statements))
end
function all_stochastic_statements(state::CompileState)
    return Iterators.flatten((state.stochastic_statements, state.stochastic_for_statements))
end
function all_for_statements(state::CompileState)
    return Iterators.flatten((
        state.logical_for_statements, state.stochastic_for_statements
    ))
end
function not_for_statements(state::CompileState)
    return Iterators.flatten((state.logical_statements, state.stochastic_statements))
end

function get_statement(state::CompileState, id::Int)
    logical_len = length(state.logical_statements)
    stochastic_len = length(state.stochastic_statements)
    logical_for_len = length(state.logical_for_statements)

    if id <= logical_len
        return state.logical_statements[id]
    elseif id <= logical_len + stochastic_len
        return state.stochastic_statements[id - logical_len]
    elseif id <= logical_len + stochastic_len + logical_for_len
        return state.logical_for_statements[id - logical_len - stochastic_len]
    else
        return state.stochastic_for_statements[id - logical_len - stochastic_len - logical_for_len]
    end
end
