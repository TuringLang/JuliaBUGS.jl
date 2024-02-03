struct Statement{ET}
    rhs_vars
    rhs_funs
    lhs
    rhs
end

function Statement(expr::Expr, data)
    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    rhs_vars, rhs_funs = get_vars_and_funs_in_expr(rhs)
    return Statement{sign}(
        rhs_vars, rhs_funs, simplify_lhs(data, lhs), rhs
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
    loop_vars
    rhs_vars
    rhs_funs
    bounds
    lhs
    rhs
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
    
    rhs_vars, rhs_funs = get_vars_and_funs_in_expr(rhs)

    bounds = map(bounds) do bound_expr
        bound = simple_arithmetic_eval(data, bound_expr)
        @assert bound isa UnitRange
        return bound
    end

    return ForStatement{sign}(
        Tuple(loop_vars),
        Tuple(setdiff(rhs_vars, loop_vars)),
        Tuple(rhs_funs),
        Tuple(bounds),
        lhs,
        rhs,
    )
end

function Base.show(io::IO, for_statement::ForStatement{ET}) where {ET}
    # reconstruct the Expr
    expr = if ET === :(=)
        MacroTools.@q($(for_statement.lhs) = $(for_statement.rhs))
    else
        MacroTools.@q($(for_statement.lhs) ~ $(for_statement.rhs))
    end
    for (loop_var, bound) in reverse(collect(zip(for_statement.loop_vars, for_statement.bounds)))
        expr = MacroTools.@q for $loop_var in $bound
                $expr
            end
    end
    print(io, expr)
end

is_logical(::Union{Statement{T},ForStatement{T}}) where {T} = T == :(=)

get_vars_and_funs_in_expr(::Number) = [], []
get_vars_and_funs_in_expr(rhs::Symbol) = [rhs], []
function get_vars_and_funs_in_expr(rhs)
    vars = Set{Symbol}()
    funs = Set{Symbol}()
    MacroTools.prewalk(rhs) do sub_expr
        if @capture(sub_expr, f_(args__))
            push!(funs, f)
            for arg in args
                if arg isa Symbol
                    push!(vars, arg)
                end
            end
        elseif @capture(sub_expr, v_[idxs__])
            push!(vars, v)
            for idx in idxs
                if idx isa Symbol
                    push!(vars, idx)
                end
            end
        end
        sub_expr
    end
    return collect(vars), collect(setdiff(funs, (:*, :+, :-, :/, :^, :(:)))) # allow :^
end
