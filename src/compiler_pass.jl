abstract type CompilerPass end

@inline is_deterministic(expr::Expr) = Meta.isexpr(expr, :(=))
@inline is_stochastic(expr::Expr) = Meta.isexpr(expr, :call) && expr.args[1] == :(~)

function analyze_program(pass::CompilerPass, expr::Expr, env::NamedTuple)
    for statement in expr.args
        if is_deterministic(statement) || is_stochastic(statement)
            analyze_assignment(pass, statement, env)
        elseif Meta.isexpr(statement, :for)
            analyze_for_loop(pass, statement, env)
        else
            error("Unsupported expression in top level: $statement")
        end
    end
    return post_process(pass, expr, env)
end

function analyze_for_loop(pass::CompilerPass, expr::Expr, env::NamedTuple)
    loop_var, lb, ub, body = decompose_for_expr(expr)
    lb = Int(evaluate(lb, env))
    ub = Int(evaluate(ub, env))

    for i in lb:ub
        for statement in body.args
            env = merge(env, NamedTuple{(loop_var,)}((i,)))
            if is_deterministic(statement) || is_stochastic(statement)
                analyze_assignment(pass, statement, env)
            elseif Meta.isexpr(statement, :for)
                analyze_for_loop(pass, statement, env)
            else
                error("Unsupported expression in for loop body: $statement")
            end
        end
    end
end

function analyze_assignment end

function post_process end

@enum VariableTypes begin
    Logical
    Stochastic
    Transformed
    Transformed_Stochastic
    Unspecified
end

"""
    CollectVariables

This analysis pass instantiates all possible left-hand sides for both deterministic and stochastic 
assignments. Checks include: (1) In a deterministic statement, the left-hand side cannot be 
specified by data; (2) In a stochastic statement, for a multivariate random variable, it cannot be 
partially observed. This pass also returns the sizes of the arrays in the model, determined by the 
largest indices.
"""
struct CollectVariables{data_arrays,arrays} <: CompilerPass
    data_scalars::Tuple{Vararg{Symbol}}
    scalars::Tuple{Vararg{Symbol}}
    data_array_sizes::NamedTuple{data_arrays}
    array_sizes::NamedTuple{arrays}
end

function CollectVariables(model_def::Expr, data::NamedTuple{data_vars}) where {data_vars}
    data_scalars, scalars, arrays, num_dims = Symbol[], Symbol[], Symbol[], Int[]
    # `extract_variable_names_and_numdims` will check if inconsistent variables' ndims
    for (name, num_dim) in pairs(extract_variable_names_and_numdims(model_def))
        if num_dim == 0
            if name in data_vars
                push!(data_scalars, name)
            else
                push!(scalars, name)
            end
        else
            push!(arrays, name)
            push!(num_dims, num_dim)
        end
    end
    data_scalars = Tuple(data_scalars)
    scalars = Tuple(scalars)
    arrays = Tuple(arrays)
    num_dims = Tuple(num_dims)

    for var in extract_variables_in_bounds_and_lhs_indices(model_def)
        if var ∉ keys(data)
            error(
                "Variable $var is used in loop bounds or indices but not defined in the data.",
            )
        end
    end

    data_arrays = Symbol[]
    data_array_sizes = SVector[]
    for k in keys(data)
        if data[k] isa AbstractArray
            push!(data_arrays, k)
            push!(data_array_sizes, SVector(size(data[k])))
        end
    end

    non_data_arrays = Symbol[]
    non_data_array_sizes = MVector[]
    for (var, num_dim) in zip(arrays, num_dims)
        if var ∉ data_vars
            push!(non_data_arrays, var)
            push!(non_data_array_sizes, MVector{num_dim}(fill(1, num_dim)))
        end
    end

    return CollectVariables(
        data_scalars,
        scalars,
        NamedTuple{Tuple(data_arrays)}(Tuple(data_array_sizes)),
        NamedTuple{Tuple(non_data_arrays)}(Tuple(non_data_array_sizes)),
    )
end

"""
    find_variables_on_lhs(expr, env)

Find all the variables on the LHS of an assignment. The variables can be either symbols or array indexing.

# Examples
```jldoctest
julia> find_variables_on_lhs(:(x[1, 2]), NamedTuple())
x[1, 2]

julia> find_variables_on_lhs(:(x[1, 2:3]), NamedTuple())
x[1, 2:3]
```
"""
find_variables_on_lhs(e::Symbol, env) = Var(e)
function find_variables_on_lhs(expr::Expr, env)
    @assert Meta.isexpr(expr, :ref)
    v, indices... = expr.args
    for (i, index) in enumerate(indices)
        indices[i] = evaluate(index, env)
    end
    return Var(v, Tuple(indices))
end

"""
    evaluate(expr, env)

Evaluate `expr` in the environment `env`.

# Examples
```jldoctest
julia> evaluate(:(x[1]), (x = [1, 2, 3],)) # array indexing is evaluated if possible
1

julia> evaluate(:(x[1] + 1), (x = [1, 2, 3],))
2

julia> evaluate(:(x[1:2]), NamedTuple()) |> Meta.show_sexpr # ranges are evaluated
(:ref, :x, 1:2)

julia> evaluate(:(x[1:2]), (x = [1, 2, 3],))
2-element Vector{Int64}:
 1
 2

julia> evaluate(:(x[1:3]), (x = [1, 2, missing],)) # when evaluate an array, if any element is missing, original expr is returned
:(x[1:3])

julia> evaluate(:(x[y[1] + 1] + 1), NamedTuple()) # if a ref expr can't be evaluated, it's returned as is
:(x[y[1] + 1] + 1)

julia> evaluate(:(sum(x[:])), (x = [1, 2, 3],)) # function calls are evaluated if possible
6

julia> evaluate(:(f(1)), NamedTuple()) # if a function call can't be evaluated, it's returned as is
:(f(1))
"""
evaluate(expr::Number, env) = expr
evaluate(expr::UnitRange, env) = expr
evaluate(expr::Colon, env) = expr
function evaluate(expr::Symbol, env::NamedTuple{variable_names}) where {variable_names}
    if expr == :(:)
        return Colon()
    else
        if expr in variable_names
            return env[expr] === missing ? expr : env[expr]
        else
            return expr
        end
    end
end
function evaluate(expr::Expr, env::NamedTuple{variable_names}) where {variable_names}
    if Meta.isexpr(expr, :ref)
        var, indices... = expr.args
        all_resolved = true
        for i in eachindex(indices)
            indices[i] = evaluate(indices[i], env)
            if indices[i] isa Float64
                indices[i] = Int(indices[i])
            end
            all_resolved = all_resolved && indices[i] isa Union{Int,UnitRange{Int},Colon}
        end
        if var in variable_names
            if all_resolved
                value = env[var][indices...]
                if is_resolved(value)
                    return value
                else
                    return Expr(:ref, var, indices...)
                end
            end
        else
            return Expr(:ref, var, indices...)
        end
    elseif Meta.isexpr(expr, :call)
        f, args... = expr.args
        all_resolved = true
        for i in eachindex(args)
            args[i] = evaluate(args[i], env)
            all_resolved = all_resolved && is_resolved(args[i])
        end
        if all_resolved
            if f === :(:)
                return UnitRange(Int(args[1]), Int(args[2]))
            elseif f ∈ BUGSPrimitives.BUGS_FUNCTIONS ∪ (:+, :-, :*, :/, :^)
                _f = getfield(BUGSPrimitives, f)
                return _f(args...)
            else
                return Expr(:call, f, args...)
            end
        else
            return Expr(:call, f, args...)
        end
    else
        error("Unsupported expression: $var")
    end
end

is_resolved(::Missing) = false
is_resolved(::Union{Int,Float64}) = true
is_resolved(::Array{<:Union{Int,Float64}}) = true
is_resolved(::Array{Missing}) = false
is_resolved(::Union{Symbol,Expr}) = false
is_resolved(::Any) = false

@inline function is_specified_by_data(
    data::NamedTuple{data_keys}, var::Symbol
) where {data_keys}
    if var ∉ data_keys
        return false
    else
        if data[var] isa AbstractArray
            error("In BUGS, implicit indexing on the LHS is not allowed.")
        else
            return true
        end
    end
end
@inline function is_specified_by_data(
    data::NamedTuple{data_keys},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int,UnitRange{Int}}},
) where {data_keys}
    if var ∉ data_keys
        return false
    else
        values = data[var][indices...]
        if values isa AbstractArray
            if eltype(values) === Missing
                return false
            elseif eltype(values) <: Union{Int,Float64}
                return true
            else
                return any(!ismissing, values)
            end
        else
            if values isa Missing
                return false
            elseif values isa Union{Int,Float64}
                return true
            else
                error("Unexpected type: $(typeof(values))")
            end
        end
    end
end

@inline function is_partially_specified_as_data(
    data::NamedTuple{data_keys},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int,UnitRange{Int}}},
) where {data_keys}
    if var ∉ data_keys
        return false
    else
        values = data[var][indices...]
        return values isa AbstractArray && any(ismissing, values) && any(!ismissing, values)
    end
end

function analyze_assignment(pass::CollectVariables, expr::Expr, env::NamedTuple)
    lhs_expr = Meta.isexpr(expr, :(=)) ? expr.args[1] : expr.args[2]
    v = simplify_lhs(env, lhs_expr)

    if v isa Symbol
        handle_symbol_lhs(pass, expr, v, env)
    else
        handle_ref_lhs(pass, expr, v, env)
    end
end

function handle_symbol_lhs(::CollectVariables, expr::Expr, v::Symbol, env::NamedTuple)
    if Meta.isexpr(expr, :(=)) && is_specified_by_data(env, v)
        error("Variable $v is specified by data, can't be assigned to.")
    end
end

function handle_ref_lhs(pass::CollectVariables, expr::Expr, v::Tuple, env::NamedTuple)
    var, indices... = v
    if Meta.isexpr(expr, :(=))
        if is_specified_by_data(env, var, indices...)
            error(
                "$var[$(join(indices, ", "))] partially observed, not allowed, rewrite so that the variables are either all observed or all unobserved.",
            )
        end
        update_array_sizes_for_assignment(pass, var, env, indices...)
    else
        if is_partially_specified_as_data(env, var, indices...)
            error(
                "$var[$(join(indices, ", "))] partially observed, not allowed, rewrite so that the variables are either all observed or all unobserved.",
            )
        end
        update_array_sizes_for_assignment(pass, var, env, indices...)
    end
end

function update_array_sizes_for_assignment(
    pass::CollectVariables,
    var::Symbol,
    ::NamedTuple{data_vars},
    indices::Vararg{Union{Int,UnitRange{Int}}},
) where {data_vars}
    # `is_specified_by_data` checks if the index is inbound
    if var ∉ data_vars
        for i in eachindex(pass.array_sizes[var])
            pass.array_sizes[var][i] = max(pass.array_sizes[var][i], last(indices[i]))
        end
    end
end

function post_process(pass::CollectVariables, expr::Expr, env::NamedTuple)
    return Set{Symbol}(pass.scalars), Dict(pairs(pass.array_sizes))
end

"""
    DataTransformation

Statements with a right-hand side that can be fully evaluated using the data are processed 
in this analysis pass, which computes these values. This achieves a similar outcome to 
Stan's `transformed parameters` block, but without requiring explicit specificity.

Conceptually, this is akin to `constant propagation` in compiler optimization, as both 
strategies aim to accelerate the optimized program by minimizing the number of operations.

It is crucial to highlight that computing data transformations plays a significant role 
in ensuring the compiler's correctness. BUGS prohibits the repetition of the same variable 
(be it a scalar or an array element) on the LHS more than once. The sole exception exists 
when the variable is computable within this pass, in which case it is regarded equivalently 
to data.
"""
mutable struct DataTransformation <: CompilerPass
    new_value_added::Bool
    const transformed_variables
end

function DataTransformation(scalar::Set, variable_array_sizes::Dict)
    transformed_variables = Dict()

    for s in scalar
        transformed_variables[s] = missing
    end

    for (k, v) in variable_array_sizes
        transformed_variables[k] = Array{Union{Missing,Real}}(missing, v...)
    end

    return DataTransformation(false, transformed_variables)
end

function has_value(transformed_variables, v::Var)
    if v isa Scalar
        return !ismissing(transformed_variables[v.name])
    elseif v isa ArrayElement
        return !ismissing(transformed_variables[v.name][v.indices...])
    else
        return all(x -> !ismissing(x), transformed_variables[v.name][v.indices...])
    end
end

function analyze_assignment(pass::DataTransformation, expr::Expr, env::NamedTuple)
    if Meta.isexpr(expr, :(=))
        lhs = find_variables_on_lhs(expr.args[1], env)

        if has_value(pass.transformed_variables, lhs)
            return nothing
        end

        rhs = evaluate(
            expr.args[2], merge_with_coalescence(env, pass.transformed_variables)
        )
        if is_resolved(rhs)
            if !pass.new_value_added
                pass.new_value_added = true
            end
            if lhs isa Scalar
                pass.transformed_variables[lhs.name] = rhs
            else
                pass.transformed_variables[lhs.name][lhs.indices...] = rhs
            end
        end
    end
end

function post_process(pass::DataTransformation, expr, env)
    return pass.new_value_added, pass.transformed_variables
end

struct PostChecking <: CompilerPass
    transformed_variables
    is_data::Dict # used to identify if a variable is a data (including transformed variable)
    definition_bit_map::Dict # used to identify repeated assignment
    logical_or_stochastic::Dict # used to identify logical or stochastic assignment
end

function PostChecking(data::NamedTuple, transformed_variables::Dict)
    is_data = Dict()
    definition_bit_map = Dict()
    logical_or_stochastic = Dict()

    all_vars = merge_with_coalescence(data, transformed_variables)

    for k in keys(all_vars)
        v = all_vars[k]
        if ismissing(v) # scalar that is not data
            is_data[k] = false
            definition_bit_map[k] = false
            logical_or_stochastic[k] = Unspecified
        elseif v isa Number # scalar that is data
            is_data[k] = true
            definition_bit_map[k] = false
            logical_or_stochastic[k] = Unspecified
        else
            is_data[k] = .!ismissing.(v)
            logical_or_stochastic[k] = fill(Unspecified, size(v)...)
            definition_bit_map[k] = fill(false, size(v)...)
        end
    end

    return PostChecking(
        transformed_variables, is_data, definition_bit_map, logical_or_stochastic
    )
end

function analyze_assignment(pass::PostChecking, expr::Expr, env::NamedTuple)
    @inline set_value!(d::Dict, value, v::Scalar) = d[v.name] = value
    @inline set_value!(d::Dict, value, v::Var) = d[v.name][v.indices...] = value
    @inline get_value(d::Dict, v::Scalar) = d[v.name]
    @inline get_value(d::Dict, v::Var) = d[v.name][v.indices...]

    @capture(expr, lhs_expr_ ~ rhs_) || @capture(expr, lhs_expr_ = rhs_)
    lhs = find_variables_on_lhs(lhs_expr, env)
    var_type = Meta.isexpr(expr, :(=)) ? Logical : Stochastic

    for v in scalarize(lhs)
        if get_value(pass.definition_bit_map, v) # if this variable has already been seen
            if get_value(pass.logical_or_stochastic, v) == var_type
                error("Repeated assignment to $v.") # produce error even when two assignment is the same
            elseif get_value(pass.logical_or_stochastic, v) == Transformed_Stochastic
                error("Multiple repeated assignment to $v.")
            elseif get_value(pass.is_data, v)
                set_value!(pass.logical_or_stochastic, Transformed_Stochastic, v)
            else
                error(
                    "$v is assigned to by both logical and stochastic assignments, " *
                    "this is only allowed when the variable is a transformation of data.",
                )
            end
        else
            set_value!(pass.definition_bit_map, true, v)
            if get_value(pass.is_data, v) && var_type == Logical
                var_type = Transformed
            end
            set_value!(pass.logical_or_stochastic, var_type, v)
        end
    end
end

function clean_up_transformed_variables(transformed_variables)
    cleaned_transformed_variables = Dict()
    for k in keys(transformed_variables)
        v = transformed_variables[k]
        if ismissing(v)
            continue
        elseif v isa Number
            cleaned_transformed_variables[k] = v
        elseif all(ismissing, v)
            continue
        elseif all(!ismissing, v)
            cleaned_transformed_variables[k] = identity.(v)
        else
            cleaned_transformed_variables[k] = v
        end
    end
    return cleaned_transformed_variables
end

function post_process(pass::PostChecking, expr, env)
    return pass.definition_bit_map,
    clean_up_transformed_variables(pass.transformed_variables)
end

"""
    NodeFunctions

A pass that analyze node functions of variables and their dependencies.
"""
struct NodeFunctions <: CompilerPass
    array_sizes::Dict
    array_bitmap::Dict

    vars::Dict
    node_args::Dict
    node_functions::Dict
    dependencies::Dict
end
function NodeFunctions(array_sizes, array_bitmap)
    return NodeFunctions(array_sizes, array_bitmap, Dict(), Dict(), Dict(), Dict())
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
    elseif Meta.isexpr(var, :call)
        if var.args[1] === :cumulative || var.args[1] === :density
            arg1, arg2 = var.args[2:3]
            arg1 = if arg1 isa Symbol
                push!(deps, arg1)
                # no need to add to arg, as the value doesn't matter
                arg1
            elseif Meta.isexpr(arg1, :ref)
                v, indices... = arg1.args
                for i in eachindex(indices)
                    e, d, a = evaluate_and_track_dependencies(indices[i], env)
                    union!(deps, d)
                    union!(args, a)
                    indices[i] = e
                end
                if any(!is_resolved, indices)
                    error(
                        "For now, the indices of the first argument to `cumulative` and `density` must be resolved, got $indices",
                    )
                end
                push!(deps, (v, Tuple(indices)))
                # no need to add to arg, as the value doesn't matter
                Expr(:ref, v, indices...)
            else
                error(
                    "First argument to `cumulative` and `density` must be variable, got $(arg1)",
                )
            end
            e, d, a = evaluate_and_track_dependencies(arg2, env)
            union!(deps, d)
            union!(args, a)
            return Expr(:call, var.args[1], arg1, e), deps, args
        else
            fun_args = []
            for i in 2:length(var.args)
                e, d, a = evaluate_and_track_dependencies(var.args[i], env)
                push!(fun_args, e)
                union!(deps, d)
                union!(args, a)
            end

            for a in fun_args
                a isa Symbol &&
                    a != :nothing &&
                    a != :(:) &&
                    (push!(deps, a); push!(args, a))
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
    else
        error("Unexpected expression type: $var")
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
    if haskey(env, x) && env[x] isa Number
        return env[x]
    end
    return x
end
function _replace_constants_in_expr(x::Expr, env)
    if Meta.isexpr(x, :ref)
        v, indices... = x.args
        if haskey(env, v) && all(x -> x isa Union{Int,Float64}, indices)
            val = env[v][map(Int, indices)...]
            return ismissing(val) ? x : val
        else
            for i in eachindex(indices)
                indices[i] = _replace_constants_in_expr(indices[i], env)
            end
            return Expr(:ref, v, indices...)
        end
    elseif Meta.isexpr(x, :call)
        if x.args[1] === :cumulative || x.args[1] === :density
            if length(x.args) != 3
                error(
                    "`cumulative` and `density` are special functions in BUGS and takes two arguments, got $(length(x.args) - 1)",
                )
            end
            f, arg1, arg2 = x.args
            if arg1 isa Symbol
                return Expr(:call, f, arg1, _replace_constants_in_expr(arg2, env))
            elseif Meta.isexpr(arg1, :ref)
                v, indices... = arg1.args
                for i in eachindex(indices)
                    indices[i] = _replace_constants_in_expr(indices[i], env)
                end
                return Expr(
                    :call,
                    f,
                    Expr(:ref, v, indices...),
                    _replace_constants_in_expr(arg2, env),
                )
            else
                error(
                    "First argument to `cumulative` and `density` must be variable, got $(x.args[2])",
                )
            end
        elseif x.args[1] === :deviance
            @warn(
                "`deviance` function is not supported in JuliaBUGS, `deviance` will be treated as a general function."
            )
        else
            x = deepcopy(x) # because we are mutating the args
            for i in 2:length(x.args)
                x.args[i] = _replace_constants_in_expr(x.args[i], env)
            end
            return x
        end
    else
        error("Unexpected expression type: $x")
    end
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
function concretize_colon_indexing(expr, array_sizes, data)
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

function analyze_assignment(pass::NodeFunctions, expr::Expr, env::NamedTuple)
    @capture(expr, lhs_expr_ ~ rhs_expr_) || @capture(expr, lhs_expr_ = rhs_expr_)
    var_type = Meta.isexpr(expr, :(=)) ? Logical : Stochastic

    lhs_var = find_variables_on_lhs(
        Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[2] : lhs_expr, env
    )
    var_type == Logical &&
        evaluate(lhs_var, env) isa Union{Number,Array{<:Number}} &&
        return nothing

    pass.vars[lhs_var] = var_type
rhs_expr = concretize_colon_indexing(rhs_expr, pass.array_sizes, env)
    rhs = evaluate(rhs_expr, env)

    if rhs isa Symbol
        @assert lhs_var isa Union{Scalar,ArrayElement}
        node_function = MacroTools.@q ($(rhs)) -> $(rhs)
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
            non_data_vars = filter(x -> x isa Var, evaluate(rhs_var, env))
            # for now: evaluate(rhs_var, env) will produce scalarized `Var`s, so dependencies
            # may contain `Auxiliary Nodes`, this should be okay, but maybe we should keep things uniform
            # by keep `dependencies` only variables in the model, not auxiliary nodes
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
    return pass.vars,
    pass.array_sizes, pass.array_bitmap, pass.node_args, pass.node_functions,
    pass.dependencies
end
