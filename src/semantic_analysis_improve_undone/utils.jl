
function create_eval_module(data)
    m = Module(gensym(), true, true)
    Base.eval(m, :(import Core: eval; eval(expr) = Base.eval(@__MODULE__, expr)))
    @eval m begin
        using JuliaBUGS.BUGSPrimitives
        using RuntimeGeneratedFunctions
        RuntimeGeneratedFunctions.init(@__MODULE__)
    end
    for (k, v) in pairs(data)
        setproperty!(m, k, v)
    end
    return m
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
