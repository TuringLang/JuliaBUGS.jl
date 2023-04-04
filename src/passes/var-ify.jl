function getindex_to_ref(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :call) && sub_expr.args[1] == :getindex
            return Expr(:ref, sub_expr.args[2:end]...)
        else
            return sub_expr
        end
    end
end

function cast_to_integer_if_integer(x)
    # Check if x is an integer or a floating-point number with an integer value
    if isa(x, Integer) || (isa(x, AbstractFloat) && isinteger(x))
        return Int(x)  # Convert x to an integer
    else
        return x  # Return the original value
    end
end

"""
    varify_scalars(expr)

Convert all symbols in `expr` to `Var`s.

# Examples

```jldoctest
julia> expr = :(a + b + c) |> dump
Expr
  head: Symbol call
  args: Array{Any}((4,))
    1: Symbol +
    2: ArrayElement{0}
      name: Symbol a
      indices: Tuple{} ()
    3: ArrayElement{0}
      name: Symbol b
      indices: Tuple{} ()
    4: ArrayElement{0}
      name: Symbol c
      indices: Tuple{} ()

```
"""
function varify_scalars(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            for (i, arg) in enumerate(args)
                if arg isa Symbol && arg != :nothing
                    args[i] = Var(arg)
                else
                    args[i] = varify_scalars(arg)
                end
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end

"""
    varify_arrayelems(expr)

Convert all array elements in `expr` to `Var`s.

# Examples

```jldoctest
julia> expr = JuliaBUGS.eval(:(a[1, 2] + b[1, 1:2]), Dict());

julia> varify_arrayelems(expr) # b[1, 1:2] is scalarized
:(a[1, 2] + Var[b[1, 1], b[1, 2]])

```
"""
function varify_arrayelems(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            for (i, arg) in enumerate(args)
                if Meta.isexpr(arg, :ref) && all(x -> x isa Union{Number, UnitRange, Colon}, arg.args[2:end])
                    if all(x -> x isa Number, arg.args[2:end])
                        args[i] = Var(arg.args[1], Tuple(arg.args[2:end]))
                    else
                        args[i] = scalarize(Var(arg.args[1], Tuple(arg.args[2:end])))
                    end
                else
                    args[i] = varify_arrayelems(arg)
                end
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end

function ref_to_getindex(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :ref)
            return Expr(:call, :getindex, sub_expr.args...)
        else
            return sub_expr
        end
    end
end

"""
    varify_arrayvars(expr)

Convert all array variables in `expr` to `Var`s.

# Examples

```jldoctest
julia> expr = :(x[y[1] + 1] + 1); evaled_expr = JuliaBUGS.eval(expr, Dict());

julia> part_var_expr = varify_arrayelems(varify_scalars(evaled_expr));

julia> varify_arrayvars(ref_to_getindex(part_var_expr)) |> dump

'''
"""
function varify_arrayvars(expr)
    return MacroTools.prewalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            if f == :getindex
                @assert !all(x -> x isa Union{Number, UnitRange, Colon}, args[2:end])
                # @assert !isa(args[1], Var) # postwalk may revisit the same code 
                args[1] isa Var || (args[1] = Var(args[1], Tuple([Colon() for i in 1:length(args)-1])))
            end
            for (i, arg) in enumerate(args)
                if arg isa Var || arg == Colon()
                    continue
                end
                args[i] = varify_arrayvars(arg)
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end
##
varify_arrayvars(ref_to_getindex(part_var_expr))

function replace_vars(expr)
    return varify_arrayvars(ref_to_getindex(varify_arrayelems(varify_scalars(expr))))
end
