using Graphs
using MacroTools
using UnPack
import Base: in, push!

# Keep track of all variables and their ids in the model.
mutable struct Vars
    num_vars::Int
    ids::Dict
end
Vars() = Vars(0, Dict())
function push!(V::Vars, var::Union{Symbol,Tuple})
    if !haskey(V.ids, var)
        V.num_vars += 1
        V.ids[var] = V.num_vars
    end
    return V.ids[var]
end

# Keep track of all array sizes. 
mutable struct ArraySizes
    untracked::Set{Symbol} # data arrays
    sizes::Dict
end
ArraySizes() = ArraySizes(Set(), Dict())

in(var::Symbol, as::ArraySizes) = haskey(as.sizes, var)

function push!(as::ArraySizes, var::Tuple)
    @assert all(x -> x isa Union{Number,UnitRange}, var[2:end])

    arr_var, indices... = var
    if arr_var in as.untracked
        @assert length(indices) == length(as.sizes[arr_var]) "Dimension mismatch."
        @assert map(x, y -> x <= y, indices, as.sizes[arr_var]) "Array size mismatch."
    end
    max_idxs = map(x -> x isa UnitRange ? x.stop : x, indices)
    if arr_var in as
        @assert length(indices) == length(as.sizes[arr_var]) "Dimension mismatch."
        as.sizes[arr_var] = Tuple(map(x, y -> x > y ? x : y, max_idxs, as.sizes[arr_var]))
    else
        as.sizes[arr_var] = Tuple(max_idxs)
    end
end

mutable struct CompilerData
    vars::Vars
    stochastic_vars::Vector
    node_functions::Dict
    dep_graph::SimpleDiGraph
    arrays_sizes::ArraySizes
end
CompilerData() = CompilerData(Vars(), Vector(), Dict(), SimpleDiGraph(), ArraySizes())

eval(var::Number, ::Any) = var
eval(var::Symbol, env::Dict) = haskey(env, var) ? env[var] : var
function eval(var::Expr, env::Dict)
    if Meta.isexpr(var, :ref)
        MacroTools.postwalk(var) do sub_expr
            if Meta.isexpr(sub_expr, :call) && !in(sub_expr.args[1], [:+, :-, :*, :/, :(:)])
                error("At $sub_expr: Only +, -, *, / are allowed in indexing.")
            end
            return sub_expr
        end
        idxs = (ex -> eval(ex, env)).(var.args[2:end])
        if all(x -> x isa Number, idxs) && haskey(env, var.args[1])
            return getindex(env[var.args[1]], idxs...)
        else
            return Expr(:ref, var.args[1], idxs...)
        end
    else
        args = map(ex -> eval(ex, env), var.args[2:end])
        evaled_var = Expr(var.head, var.args[1], args...)
        if all(x -> x isa Number, args)
            return eval(evaled_var)
        else
            return evaled_var
        end
    end
end

variables(::Number, ::Dict, ::CompilerData) = Set()
variables(e::Symbol, ::Dict, ::CompilerData) = Set([e])
function variables(expr::Expr, env::Dict, cd::CompilerData)
    if Meta.isexpr(expr, :ref)
        evaled_expr = eval(expr, env)
        if evaled_expr isa Union{Number, Array{<:Number}}
            return Set()
        end

        # Two major complexity to handle here:
        # 1. nested indexing with variables: x[y[1]] is equivalent to getindex(x[:], y[1]), i.e. require the ability to handle colon indexing. For now, we only allow nested indexing for data arrays.
        # 2. Multivariate case: index with ranges
        # 3. missing values in data arrays

        slice_indexings = findall(x -> x isa UnitRange, evaled_expr.args)
        isempty(slice_indexings) && return Set([Tuple(evaled_expr.args)])
        length(slice_indexings) == 1 || error("Only one slicing is allowed for now.")
        index = slice_indexings[1]
        ret = []
        for i in evaled_expr.args[index]
            v = deepcopy(expr.args)
            v[index] = i
            push!(ret, Tuple(v))
        end
        return Set(ret)
    elseif Meta.isexpr(expr, :call)
        return union.(map(arg -> variables(arg, env, cd), expr.args[2:end]))
    end
    return error("Not supported expression type: $expr")
end

# return a 
function node_function(expr)
end

function assignment!(expr, env, compiler_data::CompilerData)
    @unpack vars, stochastic_vars, node_functions, dep_graph, arrays_sizes = compiler_data

    l_vars = collect(variables(expr.args[1], env, compiler_data))
    r_vars = collect(variables(expr.args[2], env, compiler_data))

    for l_var in l_vars
        if l_var isa Tuple && any(x-> !isa(x, Number), l_var[2:end])
            error("LHS indices need to be evaled to constants.")
        end
    end

    l_ids = [push!(vars, l_var) for l_var in l_vars]
    r_ids = [push!(vars, r_var) for r_var in r_vars]

    add_vertices!(dep_graph, length(vars) - nv(dep_graph))
    for l_id in l_ids
        for r_id in r_ids
            add_edge!(dep_graph, r_id, l_id)
        end
    end

    for l_id in l_ids
        node_functions[l_id] = (expr, env)
        if expr.head == :(~)
            push!(compiler_data.stochastic_vars, l_id)
        end
    end
    for l_id in l_ids
        if haskey(def_to_vars, expr)
            push!(def_to_vars[expr], l_id)
        else
            def_to_vars[expr] = [l_id]
        end
    end
    @pack! compiler_data = vars, stochastic_vars, node_functions, dep_graph, arrays_sizes
end

function for_loop!(expr, data, compiler_data, loop_vars=Dict())
    loop_var = expr.args[1].args[1]
    lb, ub = expr.args[1].args[2].args
    body = expr.args[2]
    lb, ub = eval(lb, merge(data, loop_vars)), eval(ub, merge(data, loop_vars))
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

function program(ex, data::Dict)
    compiler_data = CompilerData()

    for (k, v) in data
        if v isa Array
            compiler_data.arrays_sizes.sizes[k] = size(v)
            push!(compiler_data.arrays_sizes.untracked, k)
        else
            @assert v isa Number "data must be either a number or an array"
        end
    end

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
