function simplify_lhs(::NamedTuple, lhs::Symbol)
    return lhs
end
function simplify_lhs(data::NamedTuple, lhs::Expr)
    if @capture(lhs, var_[indices__])
        indices = map(Base.Fix1(simple_arithmetic_eval, data), indices)
        indices = map(index -> index isa UnitRange ? index : Int(index), indices)
        return :($(var)[$(indices...)])
    else
        error(
            "LHS of a statement can only be a symbol or an indexing expression, but get $lhs.",
        )
    end
end

function simple_arithmetic_eval(::NamedTuple, expr::Union{Int,UnitRange{Int}})
    return expr
end
function simple_arithmetic_eval(data::NamedTuple{names,Ts}, expr::Symbol) where {names,Ts}
    if expr ∉ names
        throw(ArgumentError("Don't know the value of $expr."))
    end
    return Int(data[expr])
end
function simple_arithmetic_eval(data::NamedTuple, expr::Expr)
    if @capture(expr, f_(args__))
        args = map(Base.Fix1(simple_arithmetic_eval, data), args)
        map(args) do arg
            if arg isa UnitRange
                error("Don't know how to do arithmetic between UnitRange and Intger.")
            else
                return Int(arg)
            end
        end
        if f == :+
            return sum(args)
        elseif f == :*
            return prod(args)
        else
            @assert length(args) == 2
            if f == :-
                return args[1] - args[2]
            elseif f == :/
                return Int(args[1] / args[2])
            elseif f == :(:)
                return UnitRange(Int(args[1]), Int(args[2]))
            else
                error("Don't know how to evaluate function $(string(f)).")
            end
        end
    elseif @capture(expr, var_[indices__])
        evaluated_indices = map(indices) do index
            simple_arithmetic_eval(data, index)
        end
        return Int(data[var][evaluated_indices...])
    else
        error("Don't know how to evaluate $expr.")
    end
end
