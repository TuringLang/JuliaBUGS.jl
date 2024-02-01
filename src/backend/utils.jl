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

function simplify_lhs(::NamedTuple{names,Ts}, lhs::Symbol) where {names,Ts}
    return lhs
end
function simplify_lhs(value_map::NamedTuple{names,Ts}, lhs::Expr) where {names,Ts}
    if @capture(lhs, var_[indices__])
        indices = map(Base.Fix1(simple_arithmetic_eval, value_map), indices)
        indices = map(index -> index isa UnitRange ? index : Int(index), indices)
        return :($(var)[$(indices...)])
    else
        error(
            "LHS of a statement can only be a symbol or an indexing expression, but get $lhs.",
        )
    end
end

# simple_arithmetic_eval is used to evaluate the indices of an array or loop bounds
# the return value is either a UnitRange or an Int
function simple_arithmetic_eval(::NamedTuple{names,Ts}, expr::Int) where {names,Ts}
    return expr
end
function simple_arithmetic_eval(
    value_map::NamedTuple{names,Ts}, expr::Symbol
) where {names,Ts}
    if expr ∉ names
        throw(ArgumentError("Don't know the value of $expr."))
    end
    return Int(value_map[expr])
end
function simple_arithmetic_eval(
    value_map::NamedTuple{names,Ts}, expr::Expr
) where {names,Ts}
    if @capture(expr, f_(args__))
        args = map(Base.Fix1(simple_arithmetic_eval, value_map), args)
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
            else # :(:)
                return UnitRange(Int(args[1]), Int(args[2]))
            end
        end
    elseif @capture(expr, var_[indices__])
        evaluated_indices = map(indices) do index
            simple_arithmetic_eval(value_map, index)
        end
        return Int(value_map[var][evaluated_indices...])
    else
        error("Don't know how to evaluate $expr.")
    end
end

# returns a vector of lenses, which allow to set the value of the loop variable without expression traversal
function get_loop_var_lenses(expr, loop_vars)
    lenses_map = Dict()
    for loop_var in loop_vars
        lenses = get_lens(expr, loop_var, Setfield.IdentityLens())
        lenses_map[loop_var] = lenses
    end
    return lenses_map
end

function get_lens(expr, target_expr, parent_lens)
    if expr isa Union{Symbol,Number} # didn't find
        return []
    end

    lenses = [] # possible multiple occurrences
    if expr.head == target_expr
        push!(lenses, parent_lens ∘ (@lens _.head))
    end
    for (i, arg) in enumerate(expr.args)
        if arg == target_expr
            push!(lenses, parent_lens ∘ (@lens _.args[i]))
        else
            child_lenses = get_lens(arg, target_expr, parent_lens ∘ (@lens _.args[i]))
            for lens in child_lenses
                push!(lenses, lens)
            end
        end
    end
    return lenses
end

function plug_in_loopvar(expr, lenses, loop_vars, values)
    @assert length(values) == length(loop_vars)
    for (loop_var, value) in zip(loop_vars, values)
        for lens in lenses[loop_var]
            expr = set(expr, lens, value)
        end
    end
    return expr
end

# # simple test
# lenses = get_loop_var_lenses(:(x[i] * j + y[i, j]), [:i, :j])
# plug_in_loopvar(:(x[i] * j + y[i, j]), lenses, [:i, :j], (2, 2)) == :(x[2] * 2 + y[2, 2])
