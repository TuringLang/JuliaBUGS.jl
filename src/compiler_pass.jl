abstract type CompilerPass end

is_deterministic(expr::Expr) = Meta.isexpr(expr, :(=))
is_stochastic(expr::Expr) = Meta.isexpr(expr, :call) && expr.args[1] == :(~)

function analyze_block(pass::CompilerPass, expr::Expr, loop_vars::NamedTuple=NamedTuple())
    if !Meta.isexpr(expr, :block)
        error("The top level expression must be a block.")
    end
    for statement in expr.args
        if is_deterministic(statement) || is_stochastic(statement)
            analyze_statement(pass, statement, loop_vars)
        elseif Meta.isexpr(statement, :for)
            loop_var, lb, ub, body = decompose_for_expr(statement)
            env = merge(pass.env, loop_vars)
            lb = Int(simple_arithmetic_eval(env, lb))
            ub = Int(simple_arithmetic_eval(env, ub))
            for loop_var_value in lb:ub
                analyze_block(pass, body, merge(loop_vars, (loop_var => loop_var_value,)))
            end
        else
            error("Unsupported expression in top level: $statement")
        end
    end
end

@enum VariableTypes::Bool begin
    Logical
    Stochastic
end

"""
    CollectVariables

This analysis pass instantiates all possible left-hand sides for both deterministic and stochastic 
assignments. Checks include: (1) In a deterministic statement, the left-hand side cannot be 
specified by data; (2) In a stochastic statement, for a multivariate random variable, it cannot be 
partially observed. This pass also returns the sizes of the arrays in the model, determined by the 
largest indices.
"""
struct CollectVariables{data_vars} <: CompilerPass
    env::NamedTuple{data_vars}
    data_scalars::Tuple{Vararg{Symbol}}
    non_data_scalars::Tuple{Vararg{Symbol}}
    data_array_sizes::NamedTuple
    non_data_array_sizes::NamedTuple
end

function CollectVariables(model_def::Expr, data::NamedTuple{data_vars}) where {data_vars}
    for var in extract_variables_in_bounds_and_lhs_indices(model_def)
        if var ∉ data_vars
            error(
                "Variable $var is used in loop bounds or indices but not defined in the data.",
            )
        end
    end

    data_scalars, non_data_scalars = Symbol[], Symbol[]
    arrays, num_dims = Symbol[], Int[]
    data_scalars, scalars, arrays, num_dims = Symbol[], Symbol[], Symbol[], Int[]
    # `extract_variable_names_and_numdims` will check if inconsistent variables' ndims
    for (name, num_dim) in pairs(extract_variable_names_and_numdims(model_def))
        if num_dim == 0
            if name in data_vars
                push!(data_scalars, name)
            else
                push!(non_data_scalars, name)
            end
        else
            push!(arrays, name)
            push!(num_dims, num_dim)
        end
    end

    data_arrays = Symbol[]
    data_array_sizes = SVector[]
    for k in data_vars
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

    return CollectVariables{data_vars}(
        data,
        Tuple(data_scalars),
        Tuple(non_data_scalars),
        NamedTuple{Tuple(data_arrays)}(Tuple(data_array_sizes)),
        NamedTuple{Tuple(non_data_arrays)}(Tuple(non_data_array_sizes)),
    )
end

"""
    evaluate(expr, env)

Evaluate `expr` in the environment `env`.

# Examples
```jldoctest; setup=:(using JuliaBUGS: evaluate)
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

function is_specified_by_data(data::NamedTuple{data_keys}, var::Symbol) where {data_keys}
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
function is_specified_by_data(
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

function is_partially_specified_as_data(
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

function analyze_statement(pass::CollectVariables, expr::Expr, loop_vars::NamedTuple)
    lhs_expr = is_deterministic(expr) ? expr.args[1] : expr.args[2]
    env = merge(pass.env, loop_vars)
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
        for i in eachindex(pass.non_data_array_sizes[var])
            pass.non_data_array_sizes[var][i] = max(
                pass.non_data_array_sizes[var][i], last(indices[i])
            )
        end
    end
end

function post_process(pass::CollectVariables)
    return pass.non_data_scalars, pass.non_data_array_sizes
end

"""
    CheckRepeatedAssignments

BUGS generally forbids the same variable (scalar or array location) to appear more than once. The only exception
is when a variable appear exactly twice: one for logical assignment and one for stochastic assignment, and the variable
must be a transformed data.

In this pass, we check the following cases:
- A variable appear on the LHS of multiple logical assignments
- A variable appear on the LHS of multiple stochastic assignments
- Scalars appear on the LHS of both logical and stochastic assignments

The exceptional case will be checked after `DataTransformation` pass.
"""
struct CheckRepeatedAssignments <: CompilerPass
    env::NamedTuple
    overlap_scalars::Tuple{Vararg{Symbol}}
    logical_assignment_trackers::NamedTuple
    stochastic_assignment_trackers::NamedTuple
end

function CheckRepeatedAssignments(
    model_def::Expr, data::NamedTuple{data_vars}, non_data_array_sizes
) where {data_vars}
    # repeating assignments within deterministic and stochastic arrays are checked `extract_variables_assigned_to`
    logical_scalars, stochastic_scalars, logical_arrays, stochastic_arrays = extract_variables_assigned_to(
        model_def
    )

    overlap_scalars = Tuple(intersect(logical_scalars, stochastic_scalars))

    logical_assignment_trackers = Dict{Symbol,BitArray}()
    stochastic_assignment_trackers = Dict{Symbol,BitArray}()

    for v in logical_arrays
        # `v` can't be in data
        logical_assignment_trackers[v] = falses(non_data_array_sizes[v]...)
    end

    for v in stochastic_arrays
        array_size = if v in data_vars
            size(data[v])
        else
            non_data_array_sizes[v]
        end
        stochastic_assignment_trackers[v] = falses(array_size...)
    end

    return CheckRepeatedAssignments(
        data,
        overlap_scalars,
        NamedTuple(logical_assignment_trackers),
        NamedTuple(stochastic_assignment_trackers),
    )
end

function analyze_statement(
    pass::CheckRepeatedAssignments, expr::Expr, loop_vars::NamedTuple
)
    lhs_expr = is_deterministic(expr) ? expr.args[1] : expr.args[2]
    assignment_tracker = if is_deterministic(expr)
        pass.logical_assignment_trackers
    else
        pass.stochastic_assignment_trackers
    end

    env = merge(pass.env, loop_vars)
    lhs = simplify_lhs(env, lhs_expr)
    if !(lhs isa Symbol)
        v, indices... = lhs
        set_assignment_tracker!(assignment_tracker, v, indices...)
    end
end

function set_assignment_tracker!(
    assignment_tracker::NamedTuple, v::Symbol, indices::Vararg{Union{Int,UnitRange{Int}}}
)
    if any(assignment_tracker[v][indices...])
        indices = Tuple(findall(assignment_tracker[v][indices...]))
        error("$v already assigned at indices $indices")
    end
    if eltype(indices) == Int
        assignment_tracker[v][indices...] = true
    else
        assignment_tracker[v][indices...] .= true
    end
end

function post_process(pass::CheckRepeatedAssignments)
    suspect_arrays = Dict{Symbol,BitArray}()
    overlap_arrays = intersect(
        keys(pass.logical_assignment_trackers), keys(pass.stochastic_assignment_trackers)
    )
    for v in overlap_arrays
        if any(
            pass.logical_assignment_trackers[v] .& pass.stochastic_assignment_trackers[v]
        )
            suspect_arrays[v] =
                pass.logical_assignment_trackers[v] .&
                pass.stochastic_assignment_trackers[v]
        end
    end
    return pass.overlap_scalars, suspect_arrays
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
    env::NamedTuple
    new_value_added::Bool
end

function analyze_statement(pass::DataTransformation, expr::Expr, loop_vars::NamedTuple)
    if is_deterministic(expr)
        lhs_expr, rhs_expr = expr.args[1], expr.args[2]
        env = merge(pass.env, loop_vars)
        lhs = simplify_lhs(env, lhs_expr)

        lhs_value = if lhs isa Symbol
            env[lhs]
        else
            var, indices... = lhs
            env[var][indices...]
        end
        # check if the value already exists
        if is_resolved(lhs_value)
            return nothing
        end

        rhs = evaluate(rhs_expr, env)
        if is_resolved(rhs)
            pass.new_value_added = true
            pass_env = pass.env
            if lhs isa Symbol
                pass.env = BangBang.setproperty!!(pass_env, lhs, rhs)
            else
                var, indices... = lhs
                pass_env = pass.env
                pass.env = BangBang.setproperty!!(
                    pass_env, var, BangBang.setindex!!(pass_env[var], rhs, indices...)
                )
            end
        end
    end
end

"""
    NodeFunctions

A pass that analyze node functions of variables and their dependencies.
"""
struct NodeFunctions <: CompilerPass
    env::NamedTuple
    vars::Dict
    node_args::Dict
    node_functions::Dict
    dependencies::Dict
end
function NodeFunctions(eval_env)
    return NodeFunctions(eval_env, Dict(), Dict(), Dict(), Dict())
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
julia> evaluate_and_track_dependencies(:(x[a]), (x=[missing, missing], a = missing))
(missing, (:a, (:x, 1:2)), (:x, :a))

julia> evaluate_and_track_dependencies(:(x[a]), (x=[missing, missing], a = 1))
(missing, ((:x, 1),), (:x, :a))

julia> evaluate_and_track_dependencies(:(x[y[1]+1]+a+1), (x=[missing, missing], y = [missing, missing], a = missing))
(missing, ((:y, 1), (:x, 1:2), :a), (:x, :y, :a))

julia> evaluate_and_track_dependencies(:(x[a, b]), (x = [1 2 3; 4 5 6], a = missing, b = missing))
(missing, (:a, :b, (:x, 1:2, 1:3)), (:x, :a, :b))

julia> evaluate_and_track_dependencies(:(getindex(x[1:2, 1:3], a, b)), (x = [1 2 3; 4 5 6], a = missing, b = missing))
(missing, (:a, :b), (:x, :a, :b))

julia> evaluate_and_track_dependencies(:(getindex(x[1:2, 1:3], 1, 1)), (x = [1 2 3; 4 5 6], a = missing, b = missing))
(1, (), (:x,))

julia> evaluate_and_track_dependencies(:(getindex(x[1:2, 1:3], a, b)), (x = [1 2 missing; 4 5 6], a = missing, b = missing))
(missing, ((:x, 1:2, 1:3), :a, :b), (:x, :a, :b))
```
"""
evaluate_and_track_dependencies(var::Union{Int,Float64}, env) = var, (), ()
evaluate_and_track_dependencies(var::UnitRange, env) = var, (), ()
function evaluate_and_track_dependencies(var::Symbol, env)
    if var ∈ (:nothing, :missing, :(:))
        return var, (), ()
    end
    if env[var] === missing
        return var, (var,), (var,)
    else
        return env[var], (), (var,)
    end
end
function evaluate_and_track_dependencies(var::Expr, env)
    dependencies, node_func_args = [], []
    if Meta.isexpr(var, :ref)
        v, indices... = var.args
        push!(node_func_args, v)
        for i in eachindex(indices)
            ret = evaluate_and_track_dependencies(indices[i], env)
            index = ret[1]
            indices[i] = index isa Float64 ? Int(index) : index
            dependencies = union!(dependencies, ret[2])
            node_func_args = union!(node_func_args, ret[3])
        end

        value = nothing
        if all(indices) do i
            i isa Int || i isa UnitRange{Int}
        end
            value = env[v][indices...]
            if is_resolved(value)
                return value, Tuple(dependencies), Tuple(node_func_args)
            else
                # TODO: what if value is partially missing?
                push!(dependencies, (v, indices...))
            end
        else
            push!(
                dependencies,
                (
                    v,
                    [
                        is_resolved(index) ? index : 1:size(env[v])[i] for
                        (i, index) in enumerate(indices)
                    ]...,
                ),
            )
        end
        return missing, Tuple(dependencies), Tuple(node_func_args)
    elseif Meta.isexpr(var, :call)
        f, args... = var.args
        value = nothing
        if f === :cumulative || f === :density
            if length(args) != 2
                error(
                    "`cumulative` and `density` are special functions in BUGS and takes two arguments, got $(length(args))",
                )
            end
            arg1, arg2 = args
            if arg1 isa Symbol
                push!(dependencies, arg1)
            elseif Meta.isexpr(arg1, :ref)
                v, indices... = arg1.args
                for i in eachindex(indices)
                    ret = evaluate_and_track_dependencies(indices[i], env)
                    union!(dependencies, ret[2])
                    union!(node_func_args, ret[3])
                    indices[i] = ret[1]
                end
                if any(!is_resolved, indices)
                    error(
                        "For now, the indices of the first argument to `cumulative` and `density` must be resolved, got $indices",
                    )
                end
                push!(dependencies, (v, indices...))
            else
                error(
                    "First argument to `cumulative` and `density` must be variable, got $(arg1)",
                )
            end

            ret = evaluate_and_track_dependencies(arg2, env)
            union!(dependencies, ret[2])
            union!(node_func_args, ret[3])
            return missing, Tuple(dependencies), Tuple(node_func_args)
        elseif f === :deviance
            @warn(
                "`deviance` function is not supported in JuliaBUGS, `deviance` will be treated as a general function."
            )
        else
            for i in eachindex(args)
                ret = evaluate_and_track_dependencies(args[i], env)
                args[i] = ret[1]
                union!(dependencies, ret[2])
                union!(node_func_args, ret[3])
            end

            value = nothing
            if all(is_resolved, args) &&
                f ∈ BUGSPrimitives.BUGS_FUNCTIONS ∪ (:+, :-, :*, :/, :^, :(:), :getindex)
                return getfield(JuliaBUGS, f)(args...),
                Tuple(dependencies),
                Tuple(node_func_args)
            else
                return missing, Tuple(dependencies), Tuple(node_func_args)
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

function create_array_var(n, env)
    return Var(n, Tuple([1:i for i in size(env[n])]))
end

function analyze_statement(pass::NodeFunctions, expr::Expr, loop_vars::NamedTuple)
    env = merge(pass.env, loop_vars)

    if is_deterministic(expr)
        lhs_expr, rhs_expr = expr.args[1:2]
        var_type = Logical
    else
        lhs_expr, rhs_expr = expr.args[2:3]
        var_type = Stochastic
    end

    simplified_lhs = simplify_lhs(env, lhs_expr)
    lhs_var = if simplified_lhs isa Symbol
        Var(simplified_lhs)
    else
        v, indices... = simplified_lhs
        Var(v, Tuple(indices))
    end
    var_type == Logical &&
        evaluate(lhs_expr, env) isa Union{Number,Array{<:Number}} &&
        return nothing

    pass.vars[lhs_var] = var_type
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
        rhs_array_var = create_array_var(rhs_var.name, env)
        size(rhs_var) == size(lhs_var) ||
            error("Size mismatch between lhs and rhs at expression $expr")
        if lhs_var isa ArrayElement
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
            node_args = collect(Any, node_args)
            for i in eachindex(node_args)
                if env[node_args[i]] isa AbstractArray
                    node_args[i] = create_array_var(node_args[i], env)
                else
                    node_args[i] = Var(node_args[i])
                end
            end

            dependencies = collect(Any, dependencies)
            for i in eachindex(dependencies)
                if dependencies[i] isa Symbol
                    dependencies[i] = Var(dependencies[i])
                else
                    v, indices... = dependencies[i]
                    dependencies[i] = Var(v, Tuple(indices))
                end
            end

            args = similar(node_args, Any)
            for (i, arg) in enumerate(node_args)
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
    return pass.dependencies[lhs_var] = dependencies
end

function post_process(pass::NodeFunctions)
    return pass.vars, pass.node_args, pass.node_functions, pass.dependencies
end
