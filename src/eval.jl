"""
    eval_(expr, env)

Evaluate `expr` in the environment `env`.

# Examples
```jldoctest
julia> eval_(:(x[1]), Dict(:x => [1, 2, 3])) # array indexing is evaluated if possible
1

julia> eval_(:(x[1] + 1), Dict(:x => [1, 2, 3]))
2

julia> eval_(:(x[1:2]), Dict()) |> Meta.show_sexpr # ranges are evaluated
(:ref, :x, 1:2)

julia> eval_(:(x[1:2]), Dict(:x => [1, 2, 3])) # ranges are evaluated
2-element Vector{Int64}:
 1
 2

julia> eval_(:(x[1:3]), Dict(:x => [1, 2, missing])) # if an element is missing, the array is partially evaluated
:([1, 2, x[3]])

julia> eval_(:(x[y[z[1] + 1] + 1] + 2), Dict()) # if a ref expr can't be evaluated, it's returned as is
:(x[y[z[1] + 1] + 1] + 2)

julia> eval_(:(dnorm(x[1], 2)), Dict()) # function calls 
:(dnorm(x[y[1] + 1] + 1, 2))
"""
eval_(var::Number, ::Dict) = var
eval_(var::UnitRange, ::Dict) = var
eval_(::Colon, ::Dict) = Colon()
function eval_(var::Symbol, env::Dict)
    var == :(:) && return Colon()
    return haskey(env, var) ? env[var] : var
end
function eval_(var::Expr, env::Dict)
    if Meta.isexpr(var, :ref)
        idxs = (ex -> eval_(ex, env)).(var.args[2:end])
        !isa(idxs, Array) && (idxs = [idxs])
        if all(x -> x isa Number, idxs) && haskey(env, var.args[1])
            for i in eachindex(idxs)
                if !isa(idxs[i], Integer) && !isinteger(idxs[i])
                    error("Array indices must be integers or UnitRanges.")
                end
            end
            return env[var.args[1]][idxs...]
        elseif all(x -> x isa Union{Number, UnitRange, Colon, Array}, idxs) && haskey(env, var.args[1])
            value = getindex(env[var.args[1]], idxs...)
            if any(ismissing, value)
                if length(value) > 30 # the array is too large, don't evaluate it
                    return var
                else
                    return array_to_expr(value, var.args[1])
                end
            else
                return value
            end
        else
            return idxs_array_to_expr(var, idxs)
        end
    else # function call
        args = map(ex -> eval_(ex, env), var.args[2:end])
        try 
            return eval(Expr(var.head, var.args[1], args...))
        catch e
            return idxs_array_to_expr(var, idxs)
        end
    end
end

# if a ref expr is evaluated to an array, convert it back to an expression, so that later func_expr is not too large
# TODO: maybe not a big problem, if the underlying data is shared
function idxs_array_to_expr(var, idxs)
    for i in eachindex(idxs)
        if idxs[i] isa Array
            if length(idxs[i]) > 30 # the array is too large, don't evaluate it
                idxs[i] = var.args[2:end][i]
            else
                idxs[i] = array_to_expr(idxs[i], var.args[1])
            end
        elseif !isa(idxs[i], Union{Number, UnitRange, Colon, Expr})
            error("Type not recognized: $(typeof(idxs[i])).")
        end
    end
    return Expr(var.head, var.args[1], idxs...)
end

"""
    array_to_expr(arr::AbstractArray)

Convert an array to an expression that can be evaluated to the same array.

# Examples
```jldoctest
julia> arr1 = [1, 2, missing]; array_to_expr(arr1, :x)
:([1, 2, x[3]])

julia> arr2 = [1 2 missing; 3 missing 4]; array_to_expr(arr2, :x)
:([1 2 x[1, 3]; 3 x[2, 2] 4])

julia> arr3 = reshape([1:7..., missing], (2, 2, 2)); expr3 = array_to_expr(arr3, :x)
:([[1 3; 2 4];;; [5 7; 6 x[2, 2]]])
```
"""
function array_to_expr(arr, array_name)
    if ndims(arr) == 1
        return Expr(:vect, [element_to_expr(arr[i], array_name, (i,)) for i in 1:length(arr)]...)
    elseif ndims(arr) == 2
        rows = [Expr(:row, [element_to_expr(arr[i, j], array_name, (i, j)) for j in 1:size(arr, 2)]...) for i in 1:size(arr, 1)]
        return Expr(:vcat, rows...)
    else
        n = ndims(arr)
        perm = (1, n, collect(2:n-1)...)
        slices = [array_to_expr(permutedims(arr, perm)[:, i, :], array_name) for i in 1:size(arr, 2)]
        return Expr(:ncat, n, slices...)
    end
end

function element_to_expr(elem, array_name, idxs)
    if ismissing(elem)
        return Expr(:ref, array_name, idxs...)
    else
        return elem
    end
end
