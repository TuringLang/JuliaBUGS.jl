using Graphs, MetaGraphsNext
using MacroTools
using UnPack

mutable struct CompilerData
    vars
    node_functions 
    dep_graph
end
CompilerData() = CompilerData(Dict(), Dict(), SimpleDiGraph())

# TODO: change reference to `defs` to `node_functions`
# TODO: track array size

mutable struct Vars
    num_vars::Int
    ids::Dict()
end
function Vars()
    return Vars(0, Dict())
end
function push!(V, var)
    if !haskey(V.ids, var)
        V.num_vars += 1
        V.ids[var] = V.num_vars
    end
    return V.ids[var]
end

##
eval(var::Number, ::Any) = var
eval(var::Symbol, data) = haskey(data, var) ? data[var] : var
eval(var::Expr, data) = Meta.isexpr(var, :ref) ? getindex(data[var.args[1]], (eval.(var.args[2:end]))...) : eval_expr(var, data)
function eval_expr(var, env)
    replaced_var = MacroTools.postwalk(var) do sub_expr
        haskey(env, sub_expr) ? env[sub_expr] : sub_expr
    end
    return eval(replaced_var)
end

variables(::Number, ::Any) = Set()
variables(e::Symbol, ::Any) = Set([e])
function variables(expr::Expr, env)
    if Meta.isexpr(expr, :ref)
        replaced_expr = MacroTools.postwalk(s_e -> haskey(env, s_e) ? env[s_e] : s_e, expr)
        evaled_expr = MacroTools.postwalk(s_e -> Meta.isexpr(s_e, :call) && s_e.args[1] in [:+, :-, :*] ? eval(s_e, env) : s_e, replaced_expr)
        index = findfirst(x -> Meta.isexpr(x, :call) && x.args[1] == :(:), evaled_expr.args)
        isnothing(index) && return Set([Tuple(evaled_expr.args)])
        ret = []
        lb, ub = evaled_expr.args[index].args[2:end]
        for _i in lb:ub
            v = deepcopy(expr.args)
            v[index] = _i
            push!(ret, Tuple(v))
        end
        return Set(ret)
    elseif Meta.isexpr(expr, :call)
        r = Set()
        for arg in expr.args[2:end]
            r = union(r, variables(arg, env))
        end
        return r
    else
        error()
    end
end

function add!(vars, var)
    return haskey(vars, var) ? vars[var] : vars[var] = length(vars) + 1
end

function assignment!(expr, compiler_data::CompilerData, loop_vars=Dict())
    @unpack vars, defs, dep_graph = compiler_data
    l_vars = collect(variables(expr.args[1], loop_vars))
    r_vars = collect(variables(expr.args[2], loop_vars))

    l_ids = [add!(vars, l_var) for l_var in l_vars]
    r_ids = [add!(vars, r_var) for r_var in r_vars]

    add_vertices!(dep_graph, length(vars) - nv(dep_graph))
    for l_id in l_ids
        for r_id in r_ids
            add_edge!(dep_graph, r_id, l_id)
        end
    end

    for l_id in l_ids
        defs[l_id] = (expr, loop_vars)
    end
    for l_id in l_ids
        if haskey(def_to_vars, expr)
            push!(def_to_vars[expr], l_id)
        else
            def_to_vars[expr] = [l_id]
        end
    end
    @pack! compiler_data = vars, defs, dep_graph
end

function for_loop!(expr, data, compiler_data, loop_vars=Dict())
    loop_var = expr.args[1].args[1]
    lb, ub = expr.args[1].args[2].args
    body = expr.args[2]
    lb, ub = eval(lb, merge(data, loop_vars)), eval(ub, merge(data, loop_vars)) # allow outer loop var
    for _i in lb:ub
        for ex in body.args
            if Meta.isexpr(ex, [:(=), :(~)])
                assignment!(ex, compiler_data, merge(loop_vars, Dict(loop_var => _i)))
            elseif Meta.isexpr(ex, :for)
                for_loop!(ex, data, compiler_data, merge(loop_vars, Dict(loop_var => _i)))
            else
                error()
            end
        end
    end
end

function program(ex, data)
    compiler_data = CompilerData()
    for ex in ex.args
        if Meta.isexpr(ex, [:(=), :(~)])
            assignment!(ex, compiler_data)
        elseif Meta.isexpr(ex, :for)
            for_loop!(ex, data, compiler_data)
        else
            error()
        end
    end
    return compiler_data
end
