using MacroTools
using SymbolicUtils
using Metatheory 

# pattern matching
r = @rule (~x)[~~i] => (x, i)
r(:(x[i])) # (:x, Any[1])

function find_all_array_indices(expr)
    I = Dict{Symbol, Set{Any}}()

    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, a_[is__])
            for i in is
                if !haskey(I, a) 
                    I[a] = Set{Any}()
                end
                if i isa Real
                    isinteger(i) || error("Index $i of $sub_expr needs to be integers.")
                    push!(I[a], i)
                elseif Meta.isexpr(i, :call) && i.args[1] == :(:)
                    push!(I[a], i.args[2:end]...)
                elseif i isa Union{Symbol, Expr} && i != :(:)
                    push!(I[a], i)
                end
            end     
        end
        return sub_expr
    end

    return I
end

function rename_loop_var(ex)
    bounds = Dict{Symbol, Any}()
    expr = deepcopy(ex)
    for arg in expr.args
        if Meta.isexpr(arg, :for)
            loop_var = arg.args[1].args[1]
            body = arg.args[2]
            gen_var = gensym(loop_var)
            bounds[gen_var] = (arg.args[1].args[2].args[1], arg.args[1].args[2].args[2])
            arg.args[1].args[1] = gen_var
            arg.args[2] = MacroTools.postwalk(body) do sub_expr
                if sub_expr == loop_var
                    sub_expr = gen_var
                end
                return sub_expr
            end
            aa, bb = rename_loop_var(arg.args[2])
            arg.args[2] = aa
            bounds = merge(bounds, bb)
        end
    end
    return expr, bounds
end

function parse_logical_assignments(expr)
    L = Dict{Any, Any}()

    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, a_ = b_) && !Meta.isexpr(b, :(:))
            L[a] = b
        end
        return sub_expr
    end

    return L
end

function parse_stochastic_assignments(expr)
    S = Dict{Any, Any}()

    MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :(~))
            S[sub_expr.args[1]] = sub_expr.args[2]
        end
        return sub_expr
    end

    return S
end
