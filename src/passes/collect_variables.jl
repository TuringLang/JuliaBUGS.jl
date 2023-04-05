@enum VariableTypes begin
    Logical
    Stochastic
    TransformedStochastic # stochastic variable that is transformed by a deterministic function
end

"""
    CollectVariables

This pass collects all the possible variables appear on the LHS of both logical and stochastic assignments. Collecting the 
variable serves two purpose: 1) all the variables used on the RHS must be defined on the LHS or specified in the data; 2) we need all
the array elements to determine the size of the array variables on the RHS. The pass also collect information about the 
variable types, i.e., logical or stochastic.
"""
struct CollectVariables <: CompilerPass
    vars::Set{Var}
    var_types::Dict{Var, VariableTypes}
end
CollectVariables() = CollectVariables(Set{Var}(), Dict{Var, VariableTypes}())

"""
    find_variables_on_lhs(expr, env)

Find all the variables on the LHS of an assignment. The variables can be either symbols or array indexing.

# Examples
```jldoctest
julia> find_variables_on_lhs(:(x[1, 2]), Dict())
Var(:x, [1, 2])

julia> find_variables_on_lhs(:(x[1, 2:3]), Dict())
Var(:x, [1, 2:3])

julia> find_variables_on_lhs(:(x[f(y), 2:3]), Dict())
ERROR: Some indices on the lhs can't be fully resolved. Argument 1: f(y). 
[...]
```
"""
find_variables_on_lhs(e::Symbol, ::Dict) = Var(e)
function find_variables_on_lhs(expr::Expr, env::Dict)
    if Meta.isexpr(expr, :call)
        return find_variables_on_lhs(expr.args[2], env)
    else # Meta.isexpr(expr, :ref)
        idxs = map(x -> eval(x, env), expr.args[2:end])
        check_idxs(expr.args[1], idxs, env)
        return Var(expr.args[1], Tuple(idxs))
    end
end

"""
    check_idxs(v_name::Symbol, idxs::Array, env::Dict)

Check if the indices are valid. The indices can be either numbers, unit ranges, or colons. If the variable is a data array,
check if the indices are out of bound.

# Examples
```jldoctest
julia> check_idxs(:x, [1:2,], Dict(:x => [1, missing]))
ERROR: Some elements of x[1:2] are missing, some are not.
[...]
```
"""
function check_idxs(v_name::Symbol, idxs::Array, env::Dict)
    # check if some index is not resolved
    unresolved_indices = findall(x -> !isa(x, Union{Number, UnitRange, Colon}), idxs)
    if !isempty(unresolved_indices)
        msg = "Some indices on the lhs can't be fully resolved. "
        for i in unresolved_indices
            msg *= "Argument $i: $(expr.args[i+1]). "
        end
        error(msg)
    end
    # if the array is a data array, check if the index is out of bound
    if v_name in keys(env)
        @assert isequal(length(idxs), ndims(env[v_name])) "Dimension mismatch."
        for i in 1:length(idxs)
            if idxs[i] isa Number
                @assert idxs[i] <= size(env[v_name], i) "Index out of bound."
            elseif idxs[i] isa UnitRange
                @assert idxs[i].stop <= size(env[v_name], i) "Index out of bound."
            end
        end
    end
    # check colon index only allow in data array
    colon_idxs = findall(x -> x == Colon(), idxs)
    if !isempty(colon_idxs)
        if !haskey(v_name, env)
            error("Implicit indexing with colon is only supported when the array is a data array.")
        end
    end
    # if the variable is multi-dimensional and data, check they must all be missing or all provided
    if v_name in keys(env) && any(x -> x isa Union{UnitRange, Colon}, idxs)
        vs = env[v_name][idxs...]
        if !all(ismissing, vs) && !all(!ismissing, vs)
            error("Some elements of $v_name[$(idxs...)] are missing, some are not.")
        end
    end
end

function assignment!(pass::CollectVariables, expr::Expr, env::Dict)
    (t, t_) = Meta.isexpr(expr, :(=)) ? (Logical, Stochastic) : (Stochastic, Logical)
    v = find_variables_on_lhs(expr.args[1], env)
    isnothing(eval(v, env)) || Meta.isexpr(expr, :(=)) && error("$v is data, can't be assigned to.")
    push!(pass.vars, v)
    if !haskey(pass.var_types, v) 
        pass.var_types[v] = t
    elseif pass.var_types[v] == t_
        pass.var_types[v] = TransformedStochastic
    else 
        error("Repeated assignment to $v.")
    end
end

function post_process(pass::CollectVariables, expr, env::Dict)
    vars = pass.vars
    var_types = pass.var_types

    array_elements = Dict([v.name => [] for v in vars if v.indices != ()])    
    for v in vars
        v.indices != () && push!(array_elements[v.name], v)
    end

    array_sizes = Dict{Symbol, Vector{Int}}()
    for (k, v) in array_elements
        k in keys(env) && continue # skip data arrays
        numdims = length(v[1].indices)
        @assert all(x -> length(x.indices) == numdims, v) "$k dimension mismatch."
        array_size = Vector(falseundef, numdims)
        for i in 1:numdims
            array_size[i] = maximum(x -> isa(x.indices[i], Number) ? x.indices[i] : x.indices[i].stop, v)
        end
        array_sizes[k] = array_size
    end

    # check collision/redefinition by generating a map indicating which elements are assigned. the bit map is also used to check
    # that variable used on the rhs is defined on the lhs.
    array_bitmap = Dict([k => BitArray(undef, v...) for (k, v) in array_sizes])
    for (k, v) in array_elements
        k in keys(env) && continue # skip data arrays
        # TODO:
    end




    return vars, var_types, array_sizes
end
