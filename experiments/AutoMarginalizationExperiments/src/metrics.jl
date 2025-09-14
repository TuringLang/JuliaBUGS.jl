module Metrics

"""
    CallCounter()

Lightweight counter object. Use `Metrics.count!(ctr, :ode_solve)` to increment.
"""
Base.@kwdef mutable struct CallCounter
    dict::Dict{Symbol,Int} = Dict{Symbol,Int}()
end

count!(ctr::CallCounter, key::Symbol) = (ctr.dict[key] = get(ctr.dict, key, 0) + 1)
get(ctr::CallCounter, key::Symbol, default::Int=0) = get(ctr.dict, key, default)

"""
    @counted ctr expr

Evaluate `expr` and increment `ctr[:calls]` once. Returns the value of `expr`.
"""
macro counted(ctr, expr)
    return quote
        $(esc(ctr)).dict[:calls] = get($(esc(ctr)).dict, :calls, 0) + 1
        $(esc(expr))
    end
end

end # module

