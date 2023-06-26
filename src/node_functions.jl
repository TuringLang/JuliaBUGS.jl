struct NodeFunctions{VT} <: CompilerPass
    vars::VT
    array_sizes::Dict
    array_bitmap::Dict

    link_functions::Dict
    node_args::Dict
    node_functions::Dict
    dependencies::Dict
end
function NodeFunctions(vars, array_sizes, array_bitmap)
    return NodeFunctions(vars, array_sizes, array_bitmap, Dict(), Dict(), Dict(), Dict())
end

# TODO: this function can be too confusing
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
```
"""
evaluate_and_track_dependencies(var::Number, ::Dict) = var, Set(), Set()
evaluate_and_track_dependencies(var::UnitRange, ::Dict) = var, Set(), Set()
function evaluate_and_track_dependencies(var::Symbol, env::Dict)
    value = haskey(env, var) ? env[var] : var
    @assert !ismissing(value) "Scalar variables in data can't be missing, but $var given as missing"
    return value, Set(), Set()
end
function evaluate_and_track_dependencies(var::Expr, env::Dict)
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

        try
            return eval(Expr(var.head, var.args[1], fun_args...)), deps, args
        catch _
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
_replace_constants_in_expr(x::Symbol, env) = get(env, x, x)
function _replace_constants_in_expr(x, env)
    if Meta.isexpr(x, :ref) && all(x -> x isa Number, x.args[2:end])
        if haskey(env, x.args[1])
            val = env[x.args[1]][try_cast_to_int.(x.args[2:end])...]
            x = ismissing(val) ? x : val
        end
    elseif !isa(x, Symbol) && !isa(x, Number)
        x = deepcopy(x)
        for i in 2:length(x.args)
            x.args[i] = _replace_constants_in_expr(x.args[i], env)
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
    sizes = get(array_sizes, n, get(env, n, nothing))
    @assert sizes !== nothing "Array size information not found for variable $n"
    indices = sizes isa Array ? Tuple([1:i for i in size(sizes)]) : Tuple([1:s for s in sizes])
    return Var(n, indices)
end

try_cast_to_int(x::Integer) = x
try_cast_to_int(x::Real) = Int(x)
try_cast_to_int(x) = x # catch other types, e.g. UnitRange, Colon

# TODO: too long and confusing, need to refactor
function assignment!(pass::NodeFunctions, expr::Expr, env::Dict)
    lhs_expr, rhs_expr = expr.args[1:2]
    var_type = Meta.isexpr(expr, :(=)) ? Logical : Stochastic

    link_function = Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[1] : identity
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

    pass.link_functions[lhs_var] = link_function
    pass.node_args[lhs_var] = node_args
    pass.node_functions[lhs_var] = node_function
    return pass.dependencies[lhs_var] = dependencies
end

function post_process(pass::NodeFunctions, expr, env, vargs...)
    for (var, var_type) in pass.vars
        if var_type != Stochastic && evaluate(var, env) isa Union{Number,Array{<:Number}}
            delete!(pass.vars, var)
        end
    end
    return pass.vars,
    pass.array_sizes,
    pass.array_bitmap,
    pass.link_functions,
    pass.node_args,
    pass.node_functions,
    pass.dependencies
end
