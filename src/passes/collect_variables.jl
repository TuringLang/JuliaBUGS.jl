@enum VariableTypes begin
    Logical
    Stochastic
    """ Variables of type TransformedStochastic appear on the LHS of both logical and stochastic assignments. """
    TransformedStochastic
    Data
    """ Variables of type Dark are variables inferred to ensure fine-grain dependency tracking. """
    Dark
end

"""
    CollectVariables

This pass collects all the possible variables appear on the LHS of both logical and stochastic assignments. Collecting the 
variable serves two purpose: 1) all the variables used on the RHS must be defined on the LHS or in the data; 2) we need all
the array elements to determine the size of the array variables on the RHS. The pass also collect information about the 
variable types, i.e., logical or stochastic.
"""
struct CollectVariables <: CompilerPass
    vars::Set{Var}
    var_types::Dict{Var, VariableTypes}
end
CollectVariables() = CollectVariables(Set{Var}, Dict{Var, VariableTypes})

"""
    find_variables_on_lhs(expr, env)

Find all the variables on the LHS of an assignment. The variables can be either symbols or array indexing.

# Examples
```julia-repl
julia> find_variables_on_lhs(:(x[1, 2]), Dict())
Var(:x, [1, 2])

julia> find_variables_on_lhs(:(x[1, 2:3]), Dict())
Var(:x, [1, 2:3])

julia> find_variables_on_lhs(:(x[f(1), 2:3]), Dict())
ERROR: Some indices on the lhs can't be resolved:
 f(1) at the 1 argument
[...]
"""
find_variables_on_lhs(e::Symbol, ::Dict) = Var(e)
function find_variables_on_lhs(expr::Expr, env::Dict)
    if Meta.isexpr(expr, :call)
        @assert is_link_function "Only link functions are allowed on lhs."
        return find_variables_on_lhs(expr.args[2], env)
    else # Meta.isexpr(expr, :ref)
        idxs = map(x -> eval(x, env), expr.args[2:end])
        unresolved_indices = findall(x -> !isa(x, Union{Number, UnitRange, Colon}), idxs)
        if !isempty(unresolved_indices)
            msg = "Some indices on the lhs can't be resolved:\n"
            for i in unresolved_indices
                msg *= " $(expr.args[i + 1]) at the $i argument \n"
            end
            error(msg)
        end
        return Var(expr.args[1], idxs)
    end
end

assingment!(pass::CollectVariables, expr::Expr, env::Dict) = common_assignemnt!(pass, expr, env)
tilde_assignment!(pass::CollectVariables, expr::Expr, env::Dict) = common_assignemnt!(pass, expr, env)
function common_assignemnt!(pass::CollectVariables, expr::Expr, env::Dict)
    type = Meta.isexpr(ex, :(=)) ? Logical : Stochastic
    reverse_type = type == Logical ? Stochastic : Logical
    v = find_variables_on_lhs(expr.args[1], env)
    isnothing(eval(v, env)) || Meta.isexpr(expr, :(=)) && error("$v is data, can't be assigned to.")
    push!(pass.vars, v)
    if !haskey(pass.var_types, v) 
        pass.var_types[v] = type
    elseif pass.var_types[v] == reverse_type
        pass.var_types[v] = TransformedStochastic
    else 
        error("Repeated assignment to $v.")
    end
end

function post_process(pass::CollectVariables, expr, env::Dict)
    vars = pass.vars
    var_types = pass.var_types
    
    for var in vars
        isscalar(var) && continue
        scalarized_vs = scalarize(var)
        for v in scalarized_vs
            push!(pass.vars, v)
            pass.var_types[v] = Dark
        end
    end

    array_elements = Dict()
    for v in vars
        if v isa ArrayElement
            if !haskey(array_elements, v.name)
                array_elements[v.name] = []
            end
            push!(array_elements[v.name], v)
        end
    end

    data_arrays = Dict(k => v for (k, v) in env if v isa AbstractArray)
    array_sizes = Dict(k => collect(size(v)) for (k, v) in data_arrays)
    for (k, v) in array_sizes
        var = ArrayVariable(k, [1:s for s in v])
        push!(vars, var)
        var_types[var] = Data
    end

    for (k, v) in array_elements
        @assert all(x -> length(x.indices) == length(v[1].indices), v) "$k dimension mismatch."
        array_size = Vector(undef, length(v[1].indices))
        for i in 1:length(v[1].indices)
            array_size[i] = maximum(x -> x.indices[i], v)
        end
        if haskey(array_sizes, k)
            if !all.(array_sizes[k] >= array_size)
                error(
                    "Array $k is a data array, size can't be changed, but got $array_size."
                )
            end
        else
            array_sizes[k] = array_size
        end
    end

    return vars, var_types, array_sizes
end
