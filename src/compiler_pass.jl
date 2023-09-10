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

@enum VariableTypes::Bool begin
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

"""
    NodeFunctions

A pass that analyze node functions of variables and their dependencies.
"""
struct NodeFunctions{VT} <: CompilerPass
    vars::VT
    array_sizes::Dict
    array_bitmap::Dict

    node_args::Dict
    node_functions::Dict
    dependencies::Dict
end
function NodeFunctions(vars, array_sizes, array_bitmap)
    return NodeFunctions(vars, array_sizes, array_bitmap, Dict(), Dict(), Dict())
end

"""
    evaluate_and_track_dependencies(var, env)

Evaluate `var` in the environment `env` while tracking its dependencies and node function arguments.

This function aims to extract two related but nuanced pieces of information:
    1. Fine-grained dependency information, which is used to construct the dependency graph.
    2. Variables used for node function arguments, which only care about the variable names and types (number or array), not the index.
    
The function returns three values:
    1. An evaluated `var`.
    2. A `Set` of dependency information.
    3. A `Set` of node function arguments information.

Array elements and array variables are represented by tuples in the returned value. All `Colon` indexing is assumed to be concretized.

# Examples
```jldoctest
julia> evaluate_and_track_dependencies(:(x[a]), Dict())
(:(x[a]), Set(Any[:a, (:x, ())]), Set(Any[:a, (:x, ())]))

julia> evaluate_and_track_dependencies(:(x[a]), Dict(:a => 1))
(:(x[1]), Set(Any[(:x, (1,))]), Set(Any[(:x, ())]))

julia> evaluate_and_track_dependencies(:(x[y[1]+1]+a+1), Dict())
(:(x[y[1] + 1] + a + 1), Set(Any[:a, (:x, ()), (:y, (1,))]), Set(Any[:a, (:x, ()), (:y, ())]))

julia> evaluate_and_track_dependencies(:(getindex(x[1:2, 1:3], a, b)), Dict(:x => [1 2 3; 4 5 6]))
(:(getindex([1 2 3; 4 5 6], a, b)), Set(Any[:a, :b]), Set(Any[:a, :b, (:x, ())]))

julia> evaluate_and_track_dependencies(:(getindex(x[1:2, 1:3], a, b)), Dict(:x => [1 2 missing; 4 5 6]))
(:(getindex(Union{Missing, Int64}[1 2 missing; 4 5 6], a, b)), Set(Any[:a, :b, (:x, (1, 3))]), Set(Any[:a, :b, (:x, ())]))

julia> evaluate_and_track_dependencies(:x, Dict(:x => [1 2])) # array variables must be explicitly indexed
ERROR: AssertionError: Array indexing in BUGS must be explicit. However, `x` is accessed as a scalar.
[...]
```
"""
evaluate_and_track_dependencies(var::Number, env) = var, Set(), Set()
evaluate_and_track_dependencies(var::UnitRange, env) = var, Set(), Set()
function evaluate_and_track_dependencies(var::Symbol, env)
    value = haskey(env, var) ? env[var] : var
    @assert !ismissing(value) "Scalar variables in data can't be missing, but $var given as missing"
    @assert value isa Union{Real,Symbol} "Array indexing in BUGS must be explicit. However, `$var` is accessed as a scalar."
    return value, Set(), Set()
end
function evaluate_and_track_dependencies(var::Expr, env)
    deps, args = Set(), Set()
    if Meta.isexpr(var, :ref)
        idxs = []
        for i in 2:length(var.args)
            e, d, a = evaluate_and_track_dependencies(var.args[i], env)
            push!(idxs, e)
            union!(deps, d)
            union!(args, a)
        end

        if all(x -> x isa Number, idxs)
            if haskey(env, var.args[1]) # data, the constant is plugged in
                value = getindex(env[var.args[1]], idxs...)
                if ismissing(value) # var is a variable
                    push!(deps, (var.args[1], Tuple(idxs)))
                    push!(args, (var.args[1], ()))
                    value = Expr(var.head, var.args[1], idxs...)
                end
                return value, deps, args
            else # then it's a variable
                push!(deps, (var.args[1], Tuple(idxs))) # add the variable for fine-grain dependency
                push!(args, (var.args[1], ())) # add the corresponding array variable for node function arguments
                return Expr(var.head, var.args[1], idxs...), deps, args
            end
        elseif all(x -> x isa Union{Number,UnitRange}, idxs)
            if haskey(env, var.args[1])
                value = getindex(env[var.args[1]], idxs...)
                if any(ismissing, value)
                    missing_idxs = findall(ismissing, value)
                    for idx in missing_idxs
                        push!(deps, (var.args[1], Tuple(idx)))
                    end
                end
                push!(args, (var.args[1], ()))
                return value, deps, args
            else
                push!(deps, (var.args[1], Tuple(idxs)))
                push!(args, (var.args[1], ()))
                return Expr(var.head, var.args[1], idxs...), deps, args
            end
        end

        for i in idxs # if an index is a Symbol, then it's a variable
            i isa Symbol && i != :nothing && i != :(:) && (push!(deps, i); push!(args, i))
        end
        push!(args, (var.args[1], ()))
        push!(deps, (var.args[1], ()))
        return Expr(var.head, var.args[1], idxs...), deps, args
    else # function call
        fun_args = []
        for i in 2:length(var.args)
            e, d, a = evaluate_and_track_dependencies(var.args[i], env)
            push!(fun_args, e)
            union!(deps, d)
            union!(args, a)
        end

        for a in fun_args
            a isa Symbol && a != :nothing && a != :(:) && (push!(deps, a); push!(args, a))
        end

        if (
            var.args[1] ∈ BUGSPrimitives.BUGS_FUNCTIONS ||
            var.args[1] ∈ (:+, :-, :*, :/, :^, :(:))
        ) && all(is_resolved, args)
            return getfield(JuliaBUGS, var.args[1])(fun_args...), deps, args
        else
            return Expr(var.head, var.args[1], fun_args...), deps, args
        end
    end
end

"""
    replace_constants_in_expr(x, env)

Replace the constants in the expression `x` with their actual values from the environment `env` if the values are concrete.

# Examples
```jldoctest
julia> env = Dict(:a => 1, :b => 2, :c => 3);

julia> replace_constants_in_expr(:(a * b + c), env)
:(1 * 2 + 3)

julia> replace_constants_in_expr(:(a + b * sin(c)), env) # won't try to evaluate function calls
:(1 + 2 * sin(3))

julia> replace_constants_in_expr(:(x[a]), Dict(:x => [10, 20, 30], :a => 2)) # indexing into arrays are done if possible
20

julia> replace_constants_in_expr(:(x[a] + b), Dict(:x => [10, 20, 30], :a => 2, :b => 5))
:(20 + 5)

julia> replace_constants_in_expr(:(x[1] + y[1]), Dict(:x => [10, 20, 30], :y => [40, 50, 60]))
:(10 + 40)
```
"""
function replace_constants_in_expr(x, env)
    result = _replace_constants_in_expr(x, env)
    while result != x
        x = result
        result = _replace_constants_in_expr(x, env)
    end
    return x
end

_replace_constants_in_expr(x::Number, env) = x
function _replace_constants_in_expr(x::Symbol, env)
    if haskey(env, x)
        if env[x] isa Number # only plug in scalar variables
            return env[x]
        else # if it's an array, raise error because array indexing should be explicit
            error("$x")
        end
    end
    return x
end
function _replace_constants_in_expr(x::Expr, env)
    if Meta.isexpr(x, :ref) && all(x -> x isa Number, x.args[2:end])
        if haskey(env, x.args[1])
            val = env[x.args[1]][try_cast_to_int.(x.args[2:end])...]
            return ismissing(val) ? x : val
        end
    else # don't try to eval the function, but try to simplify
        x = deepcopy(x) # because we are mutating the args
        for i in 2:length(x.args)
            try
                x.args[i] = _replace_constants_in_expr(x.args[i], env)
            catch e
                rethrow(
                    ErrorException(
                        "Array indexing in BUGS must be explicit. However, `$(e.msg)` is accessed as a scalar.",
                    ),
                )
            end
        end
    end
    return x
end

"""
    concretize_colon_indexing(expr, array_sizes, data)

Replace all `Colon()`s in `expr` with the corresponding array size, using either the `array_sizes` or the `data` dictionaries.

# Examples
```jldoctest
julia> concretize_colon_indexing(:(f(x[1, :])), Dict(:x => (3, 4)), Dict(:x => [1 2 3 4; 5 6 7 8; 9 10 11 12]))
:(f(x[1, 1:4]))
```
"""
function concretize_colon_indexing(expr::Expr, array_sizes, data)
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, x_[idx__])
            for i in 1:length(idx)
                if idx[i] == :(:)
                    if haskey(array_sizes, x)
                        idx[i] = Expr(:call, :(:), 1, array_sizes[x][i])
                    else
                        @assert haskey(data, x)
                        idx[i] = Expr(:call, :(:), 1, size(data[x])[i])
                    end
                end
            end
            return Expr(:ref, x, idx...)
        end
        return sub_expr
    end
end

"""
    create_array_var(n, array_sizes, env)

Create an array variable with the name `n` and indices based on the sizes specified in `array_sizes` or `env`.

# Examples
```jldoctest
julia> array_sizes = Dict(:x => (2, 3));

julia> env = Dict(:y => [1 2; 3 4]);

julia> create_array_var(:x, array_sizes, env)
x[1:2, 1:3]

julia> create_array_var(:y, array_sizes, env)
y[1:2, 1:2]
```
"""
function create_array_var(n, array_sizes, env)
    if haskey(env, n)
        indices = Tuple([1:i for i in size(env[n])])
    elseif haskey(array_sizes, n)
        indices = Tuple([1:i for i in array_sizes[n]])
    else
        error("Array size information not found for variable $n")
    end
    return Var(n, indices)
end

try_cast_to_int(x::Integer) = x
try_cast_to_int(x::Real) = Int(x) # will error if !isinteger(x)
try_cast_to_int(x) = x # catch other types, e.g. UnitRange, Colon

function assignment!(pass::NodeFunctions, expr::Expr, env)
    lhs_expr, rhs_expr = expr.args[1:2]
    var_type = Meta.isexpr(expr, :(=)) ? Logical : Stochastic

    link_function = Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[1] : :identity
    # disallow link functions in stochastic assignments
    if link_function != :identity
        error(
            "Link functions $link_function in stochastic assignment expression $expr are not permited.",
        )
    end

    lhs_var = find_variables_on_lhs(
        Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[2] : lhs_expr, env
    )
    var_type == Logical &&
        evaluate(lhs_var, env) isa Union{Number,Array{<:Number}} &&
        return nothing

    rhs_expr = concretize_colon_indexing(rhs_expr, pass.array_sizes, env)
    rhs = evaluate(rhs_expr, env)

    if rhs isa Symbol
        @assert lhs isa Union{Scalar,ArrayElement}
        node_function = :identity
        node_args = [Var(rhs)]
        dependencies = [Var(rhs)]
    elseif Meta.isexpr(rhs, :ref) &&
        all(x -> x isa Union{Number,UnitRange}, rhs.args[2:end])
        @assert var_type == Logical # if rhs is a variable, then the expression must be logical
        rhs_var = Var(rhs.args[1], Tuple(rhs.args[2:end]))
        rhs_array_var = create_array_var(rhs_var.name, pass.array_sizes, env)
        size(rhs_var) == size(lhs_var) ||
            error("Size mismatch between lhs and rhs at expression $expr")
        if lhs_var isa ArrayElement
            @assert pass.array_bitmap[rhs_var.name][rhs_var.indices...] "Variable $rhs_var is not defined."
            node_function = MacroTools.@q ($(rhs_var.name)::Array) ->
                $(rhs_var.name)[$(rhs_var.indices...)]
            node_args = [rhs_array_var]
            dependencies = [rhs_var]
        else
            # rhs is not evaluated into a concrete value, then at least some elements of the rhs array are not data
            non_data_vars = filter(x -> x isa Var, evaluate(rhs, env))
            for v in non_data_vars
                @assert pass.array_bitmap[v.name][v.indices...] "Variable $v is not defined."
            end
            node_function = MacroTools.@q ($(rhs_var.name)::Array) ->
                $(rhs_var.name)[$(rhs_var.indices...)]
            node_args = [rhs_array_var]
            dependencies = non_data_vars
        end
    else
        rhs_expr = replace_constants_in_expr(rhs_expr, env)
        evaled_rhs, dependencies, node_args = evaluate_and_track_dependencies(rhs_expr, env)

        # TODO: since we are not evaluating the node function expressions anymore, we don't have to store the expression like anonymous functions 
        # rhs can be evaluated into a concrete value here, because including transformed variables in the data
        # is effectively constant propagation
        if is_resolved(evaled_rhs)
            node_function = Expr(:(->), Expr(:tuple), Expr(:block, evaled_rhs))
            node_args = []
            # we can also directly save the evaled variable to `env` and later convert to var_store
            # issue is that we need to do this in steps, const propagation need to a separate pass
            # otherwise the variable in previous expressions will not be evaluated to the concrete value
        else
            dependencies, node_args = map(
                x -> map(x) do x_elem
                    if x_elem isa Symbol
                        return Var(x_elem)
                    elseif x_elem isa Tuple && last(x_elem) == ()
                        return create_array_var(first(x_elem), pass.array_sizes, env)
                    else
                        return Var(first(x_elem), last(x_elem))
                    end
                end,
                map(collect, (dependencies, node_args)),
            )

            rhs_expr = MacroTools.postwalk(rhs_expr) do sub_expr
                if @capture(sub_expr, arr_[idxs__])
                    new_idxs = [
                        idx isa Integer ? idx : :(JuliaBUGS.try_cast_to_int($(idx))) for
                        idx in idxs
                    ]
                    return Expr(:ref, arr, new_idxs...)
                end
                return sub_expr
            end

            args = convert(Array{Any}, deepcopy(node_args))
            for (i, arg) in enumerate(args)
                if arg isa ArrayVar
                    args[i] = Expr(:(::), arg.name, :Array)
                elseif arg isa Scalar
                    args[i] = arg.name
                else
                    error("Unexpected argument type: $arg")
                end
            end
            node_function = Expr(:(->), Expr(:tuple, args...), rhs_expr)
        end
    end

    pass.node_args[lhs_var] = node_args
    pass.node_functions[lhs_var] = node_function
    pass.dependencies[lhs_var] = dependencies
    return nothing
end

function post_process(pass::NodeFunctions, expr, env, vargs...)
    for (var, var_type) in pass.vars
        if var_type != Stochastic && evaluate(var, env) isa Union{Number,Array{<:Number}}
            delete!(pass.vars, var)
        end
    end
    return pass.vars,
    pass.array_sizes, pass.array_bitmap, pass.node_args, pass.node_functions,
    pass.dependencies
end
