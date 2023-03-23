struct CollectVariables <: CompilerPass
    vars::Vars
    var_types::Dict
end

CollectVariables() = CollectVariables(Vars(), Dict())

find_variables_on_lhs(e::Symbol, ::Dict) = Var(e)
function find_variables_on_lhs(expr::Expr, env::Dict)
    if Meta.isexpr(expr, :call)
        @assert expr.args[1] in keys(INVERSE_LINK_FUNCTION) "Only link functions are allowed on lhs."
        return find_variables_on_lhs(expr.args[2], env)
    end
    @assert Meta.isexpr(expr, :ref) "Only symbol or array indexing is allowed on lhs."
    idxs = map(x -> eval(x, env), expr.args[2:end])
    msgs = map(warn_indices, idxs)
    isempty(join(msgs)) || error(join(msgs))
    return Var(expr.args[1], idxs)
end

warn_indices(expr::Number) = ""
warn_indices(expr::UnitRange) = ""
function warn_indices(expr)
    buffer = IOBuffer()
    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            print(buffer, "Function call $f is not allowed on lhs. ")
        end
        return sub_expr
    end
    msg = String(take!(buffer))
    isempty(msg) || return msg
    MacroTools.postwalk(expr) do sub_expr
        if sub_expr isa Symbol
            print(buffer, "Variable $sub_expr can't be resolved. ")
        end
        return sub_expr
    end
    return String(take!(buffer))
end

function lhs(::CollectVariables, expr, env::Dict)
    return find_variables_on_lhs(expr, env)
end

function assignment!(pass::CollectVariables, expr::Expr, env::Dict)
    v = lhs(pass, expr.args[1], env)
    var_type = expr.head == :(=) ? :logical : :stochastic
    if haskey(pass.var_types, v)
        if pass.var_types[v] == var_type
            error("Repeated assignment to $v.")
        else
            var_type = :both
        end
    end
    pass.var_types[v] = var_type
    if isscalar(v)
        push!(pass.vars, v)
        return nothing
    end
    scalarized_vs = scalarize(v)
    for v in scalarized_vs
        pass.var_types[v] = :logical
    end
    for v in union(Set([v]), Set(vcat(scalarized_vs)))
        push!(pass.vars, v)
    end
end

function post_process(pass::CollectVariables)
    vars, var_types = pass.vars, pass.var_types
    array_elements = Dict()
    for v in keys(vars)
        if v isa ArrayElement # because all ArraySlice are scalarized, we only need to check ArrayElement
            if !haskey(array_elements, v.name)
                array_elements[v.name] = []
            end
            push!(array_elements[v.name], v)
        end
    end
    array_sizes = Dict()
    for (k, v) in array_elements
        @assert all(x -> length(x.indices) == length(v[1].indices), v) "$k dimension mismatch."
        array_size = Vector(undef, length(v[1].indices))
        for i in 1:length(v[1].indices)
            array_size[i] = maximum(x -> x.indices[i], v)
        end
        array_sizes[k] = array_size
    end

    # array_map need to handle ArraySlice
    array_map = Dict()
    for (k, v) in array_sizes
        array_map[k] = zeros(Int, v...)
    end
    for v in keys(vars)
        if v isa ArrayElement
            array_map[v.name][v.indices...] = vars[v]
        end
    end

    # check if arrays in array_map has zeros
    for (k, v) in array_map
        for i in CartesianIndices(v)
            v_ele = v[i]
            if iszero(v_ele)
                @warn("Array $k has holes at $(Tuple(i)).")
            end
        end
    end

    for v in keys(vars)
        if v isa ArraySlice
            # TODO: generalize index to allow holes
            array_var = ArrayVariable(v.name, [1:s for s in size(array_map[v.name])])
            if v == array_var
                id = vars[v]
                type = var_types[v]
                delete!(vars, v)
                delete!(var_types, v)
                vars[array_var] = id
                var_types[array_var] = type
            end
        end
    end

    # TODO: add ArrayVariables and all the scalarized ArrayElements is conservative, can later evict these variables from the graph
    for k in keys(array_map)
        array_var = ArrayVariable(k, [1:s for s in size(array_map[k])])
        haskey(vars, array_var) && continue
        push!(vars, array_var)
        var_types[array_var] = :logical # added ArrayVariable is always logical
    end

    return vars, array_map, var_types
end
