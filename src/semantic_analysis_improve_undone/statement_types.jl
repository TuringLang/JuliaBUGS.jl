struct Statement{ET}
    lhs::Union{Symbol,Expr}
    rhs::Union{Symbol,Int,Float64,Expr}

    rhs_scalars::Tuple{Vararg{Symbol}}
    rhs_array_vars::Tuple{Vararg{Tuple{Symbol,Vararg{Int}}}}
    rhs_functions_used::Tuple{Vararg{Symbol}}
end

function Statement(expr::Expr, data::NamedTuple)
    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    rhs_scalars, rhs_array_vars = get_variables_appeared(rhs)
    rhs_functions_used = get_functions_used(rhs)
    return Statement{sign}(
        simplify_lhs(data, lhs), rhs, rhs_scalars, rhs_array_vars, rhs_functions_used
    )
end

function Base.show(io::IO, statement::Statement{ET}) where {ET}
    if ET === :(=)
        print(io, "$(statement.lhs) = $(statement.rhs)")
    else
        print(io, "$(statement.lhs) ~ $(statement.rhs)")
    end
end

struct ForStatement{ET}
    lhs::Expr
    rhs::Union{Symbol,Int,Float64,Expr}

    loop_vars::Tuple{Vararg{Symbol}}
    bounds::Tuple{Vararg{UnitRange{Int}}}

    rhs_scalars::Tuple{Vararg{Symbol}}
    rhs_array_vars::Tuple{Vararg{Tuple{Symbol,Vararg{Int}}}}
    rhs_functions_used::Tuple{Vararg{Symbol}}
end

function ForStatement(expr::Expr, data)
    loop_vars = []
    bounds = []
    while Meta.isexpr(expr, :for) # unpack nested loops
        @capture(
            expr,
            for loop_var_ in l_:h_
                body__
            end
        )
        push!(loop_vars, loop_var)
        push!(bounds, :(($l):($h)))
        expr = body[1]
    end

    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))

    if !Meta.isexpr(lhs, :ref)
        error("LHS of a statement in for-loops can not be a scalar, but get $lhs.")
    end

    # plugin the constants in the LHS expression and simplify
    lhs.args = map(lhs.args) do arg
        MacroTools.postwalk(arg) do sub_expr
            if @capture(sub_expr, x_[idxs__]) && x in keys(data) && all(isa.(idxs, (Int,)))
                value = data[x][idxs...]
                return ismissing(value) ? sub_expr : value
            elseif sub_expr isa Symbol && haskey(data, sub_expr) && data[sub_expr] isa Int
                return data[sub_expr]
            elseif @capture(sub_expr, f_(args__)) && f ∈ (:(+), :(*), :(-)) # postwalk will first visit the children and plug in the constants
                if f === :(-) && all(arg -> arg isa Int, args)
                    return args[1] - args[2]
                else
                    constant_vals = [arg for arg in args if arg isa Int]
                    s = f === :(+) ? sum(constant_vals) : prod(constant_vals)
                    args = filter(arg -> !isa(arg, Int), args)
                    return isempty(args) ? s : Expr(:call, f, append!(args, s)...)
                end
            end
            return sub_expr
        end
    end

    rhs_scalars, rhs_array_vars = get_variables_appeared(rhs)
    rhs_functions_used = get_functions_used(rhs)

    bounds = map(bounds) do bound_expr
        bound = simple_arithmetic_eval(data, bound_expr)
        if !isa(bound, UnitRange{Int})
            error("The bound of a for-loop must be a range, but get $bound_expr.")
        end
        if bound.stop < bound.start
            error("The loop bounds should be from small to large, but get $bound_expr.")
        end
        return bound
    end

    return ForStatement{sign}(
        lhs,
        rhs,
        Tuple(loop_vars),
        Tuple(bounds),
        Tuple(setdiff(rhs_scalars, loop_vars)),
        rhs_array_vars,
        rhs_functions_used,
    )
end

function Base.show(io::IO, for_statement::ForStatement{ET}) where {ET}
    # reconstruct the Expr
    expr = if ET === :(=)
        MacroTools.@q($(for_statement.lhs) = $(for_statement.rhs))
    else
        MacroTools.@q($(for_statement.lhs) ~ $(for_statement.rhs))
    end
    for (loop_var, bound) in
        reverse(collect(zip(for_statement.loop_vars, for_statement.bounds)))
        expr = MacroTools.@q for $loop_var in $bound
            $expr
        end
    end
    return print(io, expr)
end

is_logical(::Union{Statement{T},ForStatement{T}}) where {T} = T == :(=)

get_variables_appeared(::Number) = (), ()
get_variables_appeared(rhs::Symbol) = (rhs,), ()
function get_variables_appeared(rhs::Expr)
    scalars = Set{Symbol}()
    array_vars = Set{Tuple{Symbol,Vararg{Int}}}()
    MacroTools.prewalk(rhs) do sub_expr
        if @capture(sub_expr, f_(args__))
            for var in [var for var in args if var isa Symbol]
                push!(scalars, var)
            end
        elseif @capture(sub_expr, v_[idxs__])
            push!(array_vars, (v, length(idxs)))
            for var in [var for var in idxs if var isa Symbol]
                push!(scalars, var)
            end
        end
        sub_expr
    end
    return Tuple(scalars), Tuple(array_vars)
end

get_functions_used(::Union{Number,Symbol}) = ()
function get_functions_used(rhs::Expr, exclude=(:*, :+, :-, :/, :^, :(:)))
    funs = Set{Symbol}()
    MacroTools.prewalk(rhs) do sub_expr
        if @capture(sub_expr, f_(args__))
            push!(funs, f)
        end
        sub_expr
    end
    return Tuple(setdiff(funs, exclude))
end

function loop_fission(exprs::Vector{<:Any})
    loops = []
    for sub_expr in exprs
        if MacroTools.@capture(
            sub_expr,
            for loop_var_ in l_:h_
                body__
            end
        )
            for ex in body
                if Meta.isexpr(ex, :for)
                    inner_loops = loop_fission([ex])
                else
                    inner_loops = [ex]
                end
                for inner_l in inner_loops
                    push!(loops, MacroTools.@q(
                        for $loop_var in ($l):($h)
                            $inner_l
                        end
                    ))
                end
            end
        end
    end
    return loops
end

struct Statements{all_rhs_scalars,all_rhs_array_vars}
    logical_statements::Tuple{Vararg{Statement{:(=)}}}
    stochastic_statements::Tuple{Vararg{Statement{:(~)}}}
    logical_for_statements::Tuple{Vararg{ForStatement{:(=)}}}
    stochastic_for_statements::Tuple{Vararg{ForStatement{:(~)}}}
end

function Base.show(
    io::IO, state::Statements{all_rhs_array_vars, all_rhs_scalars}
) where {all_rhs_array_vars, all_rhs_scalars}
    print(io, "scalar variables: $(join(all_rhs_scalars, ", "))\n")
    print(
        io,
        "array variables: $(join(map(t -> t[1], all_rhs_array_vars), ", "))\n",
    )
    print(io, "logical_statements:\n")
    for stmt in state.logical_statements
        print(io, "    $stmt\n")
    end
    print(io, "stochastic_statements:\n")
    for stmt in state.stochastic_statements
        print(io, "    $stmt\n")
    end
    print(io, "logical_for_statements:\n")
    for stmt in state.logical_for_statements
        print(io, "$stmt\n")
    end
    print(io, "stochastic_for_statements:\n")
    for stmt in state.stochastic_for_statements
        print(io, "$stmt\n")
    end
end

function Statements(model_def::Expr, data::NamedTuple)
    logical_statements = Statement{:(=)}[]
    stochastic_statements = Statement{:(~)}[]
    logical_for_statements = ForStatement{:(=)}[]
    stochastic_for_statements = ForStatement{:(~)}[]

    assignments = filter(model_def.args) do arg
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

    for loop in loop_fission(model_def.args)
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

    lhs_scalars = Vector{Symbol}()
    lhs_array_vars = Vector{Tuple{Symbol,Vararg{Int}}}()
    for stmt in all_statements
        if stmt.lhs isa Symbol
            push!(lhs_scalars, stmt.lhs)
        else
            @capture(stmt.lhs, var_[indices__])
            push!(lhs_array_vars, (var, length(indices)))
        end
    end

    rhs_scalars = union(map(stmt -> stmt.rhs_scalars, all_statements)...)
    rhs_array_vars = union(map(stmt -> stmt.rhs_array_vars, all_statements)...)

    scalars = union(lhs_scalars, rhs_scalars)
    array_vars = union(lhs_array_vars, rhs_array_vars)

    data_scalars = [k for k in keys(data) if data[k] isa Union{Int,Float64}]
    data_array_vars = [(k, ndims(data[k])) for k in keys(data) if k ∉ data_scalars]

    for (s, a) in Iterators.product(scalars, array_vars)
        if s === a[1]
            error(
                "The scalar $s is also an array $(a[1]), in BUGS, use of array must be explicit, for instance, to represent all the elements in a vector A, use A[1:N], where N is the length of A",
            )
        end
    end

    for (a, b) in Iterators.product(array_vars, array_vars)
        if a[1] === b[1] && a[2] !== b[2]
            error("The array $(a[1]) has different dimensions. $(a[2]) and $(b[2])")
        end
    end

    for (a, b) in Iterators.product(data_array_vars, array_vars)
        if a[1] === b[1] && a[2] !== b[2]
            error(
                "The array $(a[1]) has different dimensions. $(a[2]) and $(ndims(data[a[1]]))"
            )
        end
    end

    return Statements{Tuple(array_vars),Tuple(scalars)}(
        Tuple(logical_statements),
        Tuple(stochastic_statements),
        Tuple(logical_for_statements),
        Tuple(stochastic_for_statements),
    )
end
