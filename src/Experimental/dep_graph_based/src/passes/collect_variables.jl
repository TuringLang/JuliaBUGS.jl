struct CollectVariables <: CompilerPass 
    vars::Vars
end

CollectVariables() = CollectVariables(Vars())

find_variables(e::Symbol, ::Dict) = Var(e)
function find_variables(expr::Expr, env::Dict)
    @assert Meta.isexpr(expr, :ref) "Only symbol or array indexing is allowed on lhs."
    idxs = map(x -> eval(x, env), expr.args[2:end])
    @assert all(x -> x isa Number || x isa UnitRange, idxs) "Only number or range indexing is allowed on lhs."
    return Var(expr.args[1], idxs)
end

function lhs(pass::CollectVariables, expr::Symbol, env::Dict) 
    lhs_var = find_variables(expr, env)
    return union(Set([lhs_var]), Set(vcat(scalarize(lhs_var))))
end

function assignment!(pass::CollectVariables, expr::Expr, env::Dict)
    vars = lhs(pass, expr.args[1], env)
    for v in vars
        push!(pass.vars, v)
    end
end

function post_process(pass::CollectVariables)
    vars = pass.vars
    
    arrays = Dict()
    array_sizes = Dict()
    for v in keys(vars.var_id_map)
        if v isa ArrayElement
            if !haskey(arrays, v.name)
                arrays[v.name] = []
            end
            push!(arrays[v.name], v)
        end
    end
    for (k, v) in arrays
        @assert all(x -> length(x.indices) == length(v[1].indices), v) "$k dimension mismatch."
        array_size = Vector(undef, length(v[1].indices))
        for i in 1:length(v[1].indices)
            array_size[i] = maximum(x -> x.indices[i], v)
        end 
        array_sizes[k] = array_size
    end

    arrays_map = Dict()
    for (k, v) in array_sizes
        arrays_map[k] = Array{Int}(undef, v...)
    end
    for v in keys(vars.var_id_map)
        if v isa ArrayElement
            arrays_map[v.name][v.indices...] = vars[v]
        end
    end

    # check if arrays in array_map has zeros
    for (k, v) in arrays_map
        if any(iszero, v)
            warn("Array $k has holes.")
        end
    end
    # create a new variable representing the whole array
    for k in keys(arrays_map)
        push!(vars, Var(k, [1:s for s in size(arrays_map[k])]))
    end

    return vars, arrays_map
end
