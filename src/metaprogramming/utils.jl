"""
    extract_variable_names(expr, excluded)

Return a NamedTuple mapping variable names to their dimensionality.

# Examples:
```jldoctest; setup = :(using MacroTools)
julia> expr = :((a + b) c):((a + b) c)

julia> extract_variable_names(expr, ())
(a = 0, b = 0, c = 0)

julia> extract_variable_names(expr, (:a,))
(b = 0, c = 0)

julia> expr2 = :(a[i])
:(a[i])

julia> extract_variable_names(expr2, ())
(a = 1, i = 0)

julia> extract_variable_names(expr2, (:i,))
(;a = 1)

julia> extract_variable_names(42, ())
NamedTuple()

julia> extract_variable_names(:x, (:x,))
NamedTuple()
```
"""
function extract_variable_names(::Union{Int,Float64}, ::Tuple{Vararg{Symbol}})
    return (;)
end
function extract_variable_names(expr::Symbol, excluded::Tuple{Vararg{Symbol}})
    return expr in excluded ? (;) : NamedTuple{(expr,)}((0,))
end
function extract_variable_names(expr::Expr, excluded::Tuple{Vararg{Symbol}})
    variables = Dict{Symbol,Int}()
    MacroTools.prewalk(expr) do sub_expr
        if !(sub_expr isa Expr)
            return sub_expr
        end
        if @capture(sub_expr, f_(args__))
            for arg in args
                if arg isa Symbol && !(arg in excluded)
                    variables[arg] = 0
                end
            end
        elseif @capture(sub_expr, v_[idxs__])
            variables[v] = length(idxs)
            for idx in idxs
                if idx isa Symbol && !(idx in excluded)
                    variables[idx] = 0
                end
            end
        end
        return sub_expr
    end
    return NamedTuple(variables)
end
