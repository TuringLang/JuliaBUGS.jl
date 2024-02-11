struct CompileState
    data # the original data, used for reconstructing

    value_bindings::NamedTuple{names,<:Any} # TODO: maybe specialize the value types too -- I know the dimensions

    # TODO: combine these to one Tuple, but write Iterators for separate kinds
    logical_statements::NTuple{NLS, Statement{:(=)}}
    stochastic_statements::NTuple{NSS, Statement{:(~)}}
    logical_for_statements::NTuple{NLFS, ForStatement{:(=)}}
    stochastic_for_statements::NTuple{NSFS, ForStatement{:(~)}}

    # logical statements that are fully evaluated for transformed variables
    excluded_logical_statements
    excluded_logical_for_statements

    # used for check repeated assignments
    logical_definition_bitmap
    stochastic_definition_bitmap
end

struct AllStatements{NLS,NSS,NLFS,NSFS}
    logical_statements::NTuple{NLS,Statement{:(=)}}
    stochastic_statements::NTuple{NSS,Statement{:(~)}}
    logical_for_statements::NTuple{NLFS,ForStatement{:(=)}}
    stochastic_for_statements::NTuple{NSFS,ForStatement{:(~)}}
end

function AllStatements(model_def::Expr, data::NamedTuple)
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
    
    return AllStatements(
        Tuple(logical_statements),
        Tuple(stochastic_statements),
        Tuple(logical_for_statements),
        Tuple(stochastic_for_statements),
    )
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
    
    all_statements = Iterators.flatten((
        logical_statements,
        stochastic_statements,
        logical_for_statements,
        stochastic_for_statements,
    ))

    all_rhs_scalars = union(map(stmt -> stmt.rhs_scalars, all_statements)...)
    all_rhs_array_vars = union(map(stmt -> stmt.rhs_array_vars, all_statements)...)

    for (s, a) in Iterators.product(all_rhs_scalars, all_rhs_array_vars)
        if s === a[1]
            error("The scalar $s is also an array $(a[1]), in BUGS, use of array must be explicit, for instance, to represent all the elements in a vector A, use A[1:N], where N is the length of A")
        end
    end

    for (a, b) in Iterators.product(all_rhs_array_vars, all_rhs_array_vars)
        if a[1] === b[1] && a[2] !== b[2]
            error("The array $(a[1]) has different dimensions. $(a[2]) and $(b[2])")
        end
    end

    value_binding = Dict()
    for s in all_rhs_scalars
        if s ∈ keys(data)
            value_binding[s] = data[s]
        else
            value_binding[s] = missing
        end
    end
    for a in all_rhs_array_vars
        if a[1] ∈ keys(data)
            value_binding[a] = data[a[1]]
        else
            # create a array filled with missing of numdim a[2]
            value_binding[a] = fill(missing, fill(1, a[2])...)
        end
    end

    return CompileState(
        data,
        NamedTuple(value_binding),
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

