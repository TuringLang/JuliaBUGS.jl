"""
Functional Compiler

Fundamental idea: assignments as rules for term-rewriting; pattern matching to handle indexing.
E.g. (1)x[i] matches x: array name, i: index; (2) evaluate the RHS with x, i; (3) rewrite the original x[i] term.
Do not need to unroll every loop.

Possible indices of an array = {constants, expressions with loop bounds, expressions with other variables}
Array size: lower bound = min(Possible indices of an array); upper bound = max(Possible indices of an array), which are both just 
    expressions.

Implementation idea:
1. rename the loop var so that we can decouple the programs expressions to single line expressions and a dictionary of loop bounds
2. enumerate all the possible combinations of loop bounds, then every stochastic variable will correspond to a subset of these combinations,
    if the graph is static, then finitely many stochastic can be generated.

Possible way to implement:
* Metatheory.jl can be a good base for pattern matching and term rewriting
* There might be a way to achieve this by modifying the current compiler: before and after each `substitute`, use `Symbolics.toexpr` 
    to get the expression, then pattern matching and modify rule dictionary for the next `substitute` call.
    
Pro and cons compare to the unrolling solution:
* Unrolling can be seen as aggressive caching
* Unrolling uses more memory, but unlikely to be a magnitudes more, as finally we will generate a graph, so both O(|V| + |E|)
* Unrolling based on Symbolics.jl may have some extra perks because Symbolics.jl implemented them

Current plan: this is a very interesting idea, but it is not a priority right now
"""

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
