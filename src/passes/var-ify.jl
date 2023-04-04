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
julia> expr = :(a[1, 2] + b[3, 4] + c[5, 6]) |> dump
Expr
  head: Symbol call
  args: Array{Any}((4,))
    1: Symbol +
    2: Expr
      head: Symbol ref
      args: Array{Any}((3,))
        1: Symbol a
        2: Int64 1
        3: Int64 2
    3: Expr
      head: Symbol ref
      args: Array{Any}((3,))
        1: Symbol b
        2: Int64 3
        3: Int64 4
    4: Expr
      head: Symbol ref
      args: Array{Any}((3,))
        1: Symbol c
        2: Int64 5
        3: Int64 6

```
"""
function varify_arrayelems(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            for (i, arg) in enumerate(args)
                if Meta.isexpr(arg, :ref) &&
                    all(x -> x isa Number || x isa UnitRange, arg.args[2:end])
                    if all(x -> x isa Number, arg.args[2:end])
                        args[i] = Var(arg.args[1], arg.args[2:end])
                    else
                        args[i] = scalarize(Var(arg.args[1], arg.args[2:end]))
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


function varify_arrayvars(expr, array_map, env)
    return MacroTools.postwalk(expr) do sub_expr
        @assert !Meta.isexpr(sub_expr, :ref)
        if MacroTools.@capture(sub_expr, f_(args__))
            if f == :getindex
                if !isa(args[1], Var)
                    if haskey(array_map, args[1])
                        if all(x -> x isa Number, args[2:end]) # TODO: this should be done in `varify_arrayelems`, figure out what's wrong
                            return Var(args[1], args[2:end])
                        else
                            array_size = collect(size(array_map[args[1]]))
                            array_size = map(x -> 1:x, array_size)
                            args[1] = Var(args[1], array_size)
                        end
                    else
                        @assert args[1] in keys(env)
                        array_size = collect(size(env[args[1]]))
                        array_size = map(x -> 1:x, array_size)
                        args[1] = Var(args[1], array_size)
                    end
                end
            end
            for (i, arg) in enumerate(args)
                if arg isa Var || arg == Colon()
                    continue
                end
                args[i] = varify_arrayvars(arg, array_map, env)
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end

function replace_vars(expr, array_map, env)
    return varify_arrayvars(
        ref_to_getindex(varify_arrayelems(varify_scalars(expr))), array_map, env
    )
end
