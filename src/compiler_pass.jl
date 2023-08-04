"""
    CompilerPass

Abstract supertype for all compiler passes. Concrete subtypes should store data needed and artifacts.
"""
abstract type CompilerPass end

"""
    program!(pass::CompilerPass, expr::Expr, env, vargs...)

The entry point for a compiler pass, which traverses the AST and performs specific actions like assignment and for-loop processing.
This function should be implemented for every concrete subtype of CompilerPass.

Arguments:
- pass: Instance of a concrete CompilerPass subtype.
- expr: An Expr object representing the AST to be traversed.
- env: A Dict object representing the environment.
"""
function program!(pass::CompilerPass, expr::Expr, env, vargs...)
    for ex in expr.args
        if Meta.isexpr(ex, [:(=), :(~)])
            assignment!(pass, ex, env, vargs...)
        elseif Meta.isexpr(ex, :for)
            for_loop!(pass, ex, env, vargs...)
        else
            error()
        end
    end
    return post_process(pass, expr, env, vargs...)
end

"""
    for_loop!(pass::CompilerPass, expr, env, vargs...)

Processes a for-loop from a traversed AST.
"""
function for_loop!(pass::CompilerPass, expr, env, vargs...)
    loop_var = expr.args[1].args[1]
    lb, ub = expr.args[1].args[2].args
    body = expr.args[2]
    lb, ub = evaluate(lb, env), evaluate(ub, env)
    @assert all(isinteger.((lb, ub))) "Only integer ranges are supported"
    for i in lb:ub
        for ex in body.args
            if Meta.isexpr(ex, [:(=), :(~)])
                assignment!(pass, ex, merge(env, Dict(loop_var => i)), vargs...)
            elseif Meta.isexpr(ex, :for)
                for_loop!(pass, ex, merge(env, Dict(loop_var => i)), vargs...)
            else
                error()
            end
        end
    end
end

"""
    assignment!(pass::CompilerPass, expr::Expr, env, vargs...)

Performs an assignment operation on a traversed AST. Should be implemented for every concrete subtype of CompilerPass.

Arguments:
- pass: Instance of a concrete CompilerPass subtype.
- expr: An Expr object representing the assignment operation.
- env: A Dict object representing the environment.
"""
function assignment!(::CompilerPass, expr::Expr, env, vargs...) end

"""
    post_process(pass::CompilerPass, expr, env, vargs...)

Performs any post-processing necessary after traversing the AST. Should be implemented for every concrete subtype of CompilerPass.

Arguments:
- pass: Instance of a concrete CompilerPass subtype.
- expr: An Expr object representing the traversed AST.
- env: A Dict object representing the environment.
"""
function post_process(pass::CompilerPass, expr, env, vargs...) end

@enum VariableTypes begin
    Logical
    Stochastic
end

"""
    CollectVariables

This pass collects all the possible variables appear on the LHS of both logical and stochastic assignments. 
"""
struct CollectVariables <: CompilerPass
    vars::Dict{Var,VariableTypes}
    transformed_variables::Dict{Var,Union{Number,Array{<:Number}}}
end
function CollectVariables()
    return CollectVariables(
        Dict{Var,VariableTypes}(), Dict{Var,Union{Number,Array{<:Number}}}()
    )
end

"""
    find_variables_on_lhs(expr, env)

Find all the variables on the LHS of an assignment. The variables can be either symbols or array indexing.

# Examples
```jldoctest
julia> find_variables_on_lhs(:(x[1, 2]), Dict())
x[1, 2]

julia> find_variables_on_lhs(:(x[1, 2:3]), Dict())
x[1, 2:3]
```
"""
find_variables_on_lhs(e::Symbol, env) = Var(e)
function find_variables_on_lhs(expr::Expr, env)
    @assert Meta.isexpr(expr, :ref)
    idxs = map(x -> evaluate(x, env), expr.args[2:end])
    return Var(expr.args[1], Tuple(idxs))
end

"""
    check_unresolved_indices(idxs)

Check if indices contain unresolved values and raise an error if found.

# Arguments
- `idxs`: Indices to check.

# Example
```jldoctest
julia> check_unresolved_indices([1, 2, 3])

julia> check_unresolved_indices((1, 2, :(f(x))))
ERROR: Some indices on the lhs can't be fully resolved. Argument at position 3: f(x).
[...]
```
"""
function check_unresolved_indices(idxs)
    unresolved_indices = findall(x -> !isa(x, Union{Number,UnitRange,Colon}), idxs)
    if isempty(unresolved_indices)
        return nothing
    end
    msg = "Some indices on the lhs can't be fully resolved. "
    for i in unresolved_indices
        msg *= "Argument at position $i: $(idxs[i]). "
    end
    return error(msg)
end

"""
    check_out_of_bounds(v_name::Symbol, idxs, env)

Check if the variable `v_name`'s indices are out of bounds in the given environment `env`.

# Arguments
- `v_name::Symbol`: Variable name.
- `idxs`: Indices to check.
- `env`: Current environment variables.

# Example
```jldoctest
julia> env = Dict(:A => rand(3, 3));

julia> check_out_of_bounds(:A, (1, 2), env)

julia> check_out_of_bounds(:A, (4, 3), env)
ERROR: AssertionError: Index out of bound.
[...]
```
"""
function check_out_of_bounds(v_name::Symbol, idxs, env)
    if !(v_name in keys(env))
        return nothing
    end
    array_dim_length = length(idxs)
    @assert isequal(array_dim_length, ndims(env[v_name])) "Dimension mismatch."
    for i in 1:array_dim_length
        if idxs[i] isa Number
            @assert idxs[i] <= size(env[v_name], i) "Index out of bound."
        elseif idxs[i] isa UnitRange
            @assert idxs[i].stop <= size(env[v_name], i) "Index out of bound."
        end
    end
end

"""
    check_implicit_indexing(v_name::Symbol, idxs, env)

Check if the variable `v_name`'s indices use implicit indexing with colons, and raise an error if not supported.

# Arguments
- `v_name::Symbol`: Variable name.
- `idxs`: Indices to check.
- `env`: Current environment variables.

# Example
```jldoctest
julia> env = Dict(:B => rand(2, 2));

julia> check_implicit_indexing(:B, (Colon(), 1), env)

julia> check_implicit_indexing(:C, (Colon(), 1), env)
ERROR: Implicit indexing with colon is only supported when the array is a data array.
[...]
```
"""
function check_implicit_indexing(v_name::Symbol, idxs, env)
    colon_idxs = findall(x -> x == Colon(), idxs)
    if isempty(colon_idxs)
        return nothing
    end
    if !haskey(env, v_name)
        error(
            "Implicit indexing with colon is only supported when the array is a data array."
        )
    end
end

"""
    check_partial_missing_values(v_name::Symbol, idxs, env)

Check if the variable `v_name`'s indices have partial missing values and raise an error if found.

# Arguments
- `v_name::Symbol`: Variable name.
- `idxs`: Indices to check.
- `env`: Current environment variables.

# Example
```jldoctest
julia> env = Dict(:D => [1, missing, 2]);

julia> check_partial_missing_values(:D, (1:3, ), env)
ERROR: Some elements of D[1:3] are missing, some are not.
[...]
```
"""
function check_partial_missing_values(v_name::Symbol, idxs, env)
    if !(v_name in keys(env))
        return nothing
    end
    if any(x -> x isa Union{UnitRange,Colon}, idxs)
        vs = env[v_name][idxs...]
        if !all(ismissing, vs) && !all(!ismissing, vs)
            error("Some elements of $v_name[$(idxs...)] are missing, some are not.")
        end
    end
end

"""
    check_idxs(v_name::Symbol, idxs, env)

Check the validity of the indices `idxs` for the variable `v_name` in the environment `env`.

This function checks for unresolved indices, out-of-bounds indices, unsupported implicit indexing, and partial missing values.

# Arguments
- `v_name::Symbol`: Variable name.
- `idxs`: Indices to check.
- `env`: Current environment variables.
```
"""
function check_idxs(v_name::Symbol, idxs, env)
    check_unresolved_indices(idxs)
    check_out_of_bounds(v_name, idxs, env)
    check_implicit_indexing(v_name, idxs, env)
    return check_partial_missing_values(v_name, idxs, env)
end

"""
    evaluate(var, env)

Evaluate `var` in the environment `env`.

# Examples
```jldoctest
julia> evaluate(:(x[1]), Dict(:x => [1, 2, 3])) # array indexing is evaluated if possible
1

julia> evaluate(:(x[1] + 1), Dict(:x => [1, 2, 3]))
2

julia> evaluate(:(x[1:2]), Dict()) |> Meta.show_sexpr # ranges are evaluated
(:ref, :x, 1:2)

julia> evaluate(:(x[1:2]), Dict(:x => [1, 2, 3])) # ranges are evaluated
2-element Vector{Int64}:
 1
 2

julia> evaluate(:(x[1:3]), Dict(:x => [1, 2, missing])) # when evaluate an array, if any element is missing, original expr is returned
:(x[1:3])

julia> evaluate(:(x[y[1] + 1] + 1), Dict()) # if a ref expr can't be evaluated, it's returned as is
:(x[y[1] + 1] + 1)

julia> evaluate(:(sum(x[:])), Dict(:x => [1, 2, 3])) # function calls are evaluated if possible
6

julia> evaluate(:(f(1)), Dict()) # if a function call can't be evaluated, it's returned as is
:(f(1))
"""
evaluate(var::Number, env) = var
evaluate(var::UnitRange, env) = var
evaluate(::Colon, env) = Colon()
function evaluate(var::Symbol, env)
    var == :(:) && return Colon()
    value = haskey(env, var) ? env[var] : var
    return ismissing(value) ? var : value
end
function evaluate(var::Expr, env)
    if Meta.isexpr(var, :ref)
        idxs = (ex -> evaluate(ex, env)).(var.args[2:end])
        !isa(idxs, Array) && (idxs = [idxs])
        if all(x -> x isa Number, idxs) && haskey(env, var.args[1])
            for i in eachindex(idxs)
                if !isa(idxs[i], Integer) && !isinteger(idxs[i])
                    error("Array indices must be integers or UnitRanges.")
                end
            end
            value = env[var.args[1]][Int.(idxs)...]
            return ismissing(value) ? Expr(var.head, var.args[1], idxs...) : value
        elseif all(x -> x isa Union{Number,UnitRange,Colon,Array}, idxs) &&
            haskey(env, var.args[1])
            value = getindex(env[var.args[1]], idxs...) # can use `view` here
            !any(ismissing, value) && return value
        end
        return Expr(var.head, var.args[1], idxs...)
    elseif var.args[1] ∈ BUGSPrimitives.BUGS_FUNCTIONS ||
        var.args[1] ∈ (:+, :-, :*, :/, :^, :(:)) # function call
        # elseif isdefined(JuliaBUGS, var.args[1])
        f = var.args[1]
        args = map(ex -> evaluate(ex, env), var.args[2:end])
        if all(is_resolved, args)
            return getfield(JuliaBUGS, f)(args...)
        else
            return Expr(var.head, f, args...)
        end
    else # don't try to eval the function, but try to simplify
        args = map(ex -> evaluate(ex, env), var.args[2:end])
        return Expr(var.head, var.args[1], args...)
    end
end

@inline is_resolved(x) = x isa Number || x isa Array{<:Number}

function assignment!(pass::CollectVariables, expr::Expr, env)
    lhs_expr, rhs_expr = expr.args[1:2]

    v = find_variables_on_lhs(
        Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[2] : lhs_expr, env
    )
    !isa(v, Scalar) && check_idxs(v.name, v.indices, env)
    is_resolved(evaluate(v, env)) &&
        Meta.isexpr(expr, :(=)) &&
        error("$v is data, can't be assigned to.")

    var_type = Meta.isexpr(expr, :(=)) ? Logical : Stochastic
    haskey(pass.vars, v) && var_type == pass.vars[v] && error("Repeated assignment to $v.")
    if var_type == Logical
        rhs = evaluate(rhs_expr, env)
        is_resolved(rhs) && (pass.transformed_variables[v] = rhs)
        haskey(pass.vars, v) &&
            !is_resolved(rhs) &&
            error("$v is assigned to by both logical and stochastic assignments, 
            only allowed when the variable is a transformation of data.")
        haskey(pass.vars, v) && (var_type = Stochastic)
    end
    return pass.vars[v] = var_type
end

function post_process(pass::CollectVariables, expr, env)
    # TODO: can we distinguish observed stochastic variable used in loop bounds or computing indices?

    array_elements = Dict([v.name => [] for v in keys(pass.vars) if v.indices != ()])
    for v in keys(pass.vars)
        !isa(v, Scalar) && push!(array_elements[v.name], v)
    end

    array_sizes = Dict{Symbol,Vector{Int}}()
    for (k, v) in array_elements
        k in keys(env) && continue # skip data arrays
        numdims = length(v[1].indices)
        @assert all(x -> length(x.indices) == numdims, v) "$k dimension mismatch."
        array_size = Vector(undef, numdims)
        for i in 1:numdims
            array_size[i] = maximum(
                x -> isa(x.indices[i], Number) ? x.indices[i] : x.indices[i].stop, v
            )
        end
        array_sizes[k] = array_size
    end

    transformed_variables = Dict()
    for tv in keys(pass.transformed_variables)
        if tv isa Scalar
            transformed_variables[tv.name] = pass.transformed_variables[tv]
        else
            if !haskey(transformed_variables, tv.name)
                tvs = fill(missing, array_sizes[tv.name]...)
                transformed_variables[tv.name] = convert(Array{Union{Missing,Number}}, tvs)
            end
            transformed_variables[tv.name][tv.indices...] = pass.transformed_variables[tv]
        end
    end
    for (k, v) in transformed_variables
        if v isa Array && !any(ismissing, v)
            transformed_variables[k] = convert(Array{Number}, v)
        end
    end

    # scalar is already checked in `assignment!`
    logical_bitmap = Dict([k => falses(v...) for (k, v) in array_sizes])
    stochastic_bitmap = deepcopy(logical_bitmap)
    for (k, v) in pass.vars
        k isa Scalar && continue
        k.name in keys(env) && continue # skip data arrays
        bitmap = v == Logical ? logical_bitmap : stochastic_bitmap
        for v_ in scalarize(k)
            if bitmap[v_.name][v_.indices...]
                error("Repeated assignment to $v_.")
            else
                bitmap[v_.name][v_.indices...] = true
            end
        end
    end

    # corner case: x[1:2] = something, x[3] = something, x[1:3] ~ dmnorm()
    overlap = Dict()
    for k in keys(logical_bitmap)
        overlap[k] = logical_bitmap[k] .& stochastic_bitmap[k]
    end

    for (k, v) in overlap
        if any(v)
            idxs = findall(v)
            for i in idxs
                !haskey(transformed_variables, k) &&
                    error("Logical and stochastic variables overlap on $k[$i].")
                transformed_variables[k][i...] != missing && continue
                error("Logical and stochastic variables overlap on $k[$(i...)].")
            end
        end
    end

    # used to check if a variable is defined on the lhs
    array_bitmap = Dict()
    for k in keys(logical_bitmap)
        array_bitmap[k] = logical_bitmap[k] .| stochastic_bitmap[k]
    end

    # it is possible that a logical variable is constant and never appear one the LHS of ~
    # this variable's value is captured by `transformed_variables`
    # we still include it in `vars` for now

    return pass.vars, array_sizes, transformed_variables, array_bitmap
end
