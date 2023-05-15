struct NodeFunctions{VT} <: CompilerPass
    vars::VT
    array_sizes::Dict
    array_bitmap::Dict

    link_functions::Dict
    node_args::Dict
    node_functions::Dict
    dependencies::Dict
end
NodeFunctions(vars, array_sizes, array_bitmap) = NodeFunctions(vars, array_sizes, array_bitmap, Dict(), Dict(), Dict(), Dict())

function unpack(pass::NodeFunctions)
    return pass.vars,
    pass.array_sizes,
    pass.array_bitmap,
    pass.link_functions,
    pass.node_args,
    pass.node_functions,
    pass.dependencies
end

"""
    evaluate_(var, env)

Evaluate `var` in the environment `env`. Return the evaluated value, the set of variables that `var` depends 
on, and the arguments of the node function based on `var`. Array elements and array variables are represented
by tuples in the returned value. Assume all Colon indexing has been concretized.

# Examples
julia> evaluate_(:(x[a]), Dict())
(:(x[a]), Set(Any[:a, (:x, ())]), Set(Any[:a, (:x, ())]))

julia> evaluate_(:(x[a]), Dict(:a => 1))
(:(x[1]), Set(Any[(:x, (1,))]), Set(Any[(:x, ())]))

julia> evaluate_(:(x[y[1]+1]+a+1), Dict())
(:(x[y[1] + 1] + a + 1), Set(Any[:a, (:x, ()), (:y, (1,))]), Set(Any[:a, (:x, ()), (:y, ())]))

julia> evaluate_(:(getindex(x[1:2, 1:3], a, b)), Dict(:x => [1 2 3; 4 5 6]))
(:(getindex([1 2 3; 4 5 6], a, b)), Set(Any[:a, :b]), Set(Any[:a, :b, (:x, ())]))

julia> evaluate_(:(getindex(x[1:2, 1:3], a, b)), Dict(:x => [1 2 missing; 4 5 6]))
(:(getindex(Union{Missing, Int64}[1 2 missing; 4 5 6], a, b)), Set(Any[:a, :b, (:x, (1, 3))]), Set(Any[:a, :b, (:x, ())]))
```
"""
evaluate_(var::Number, ::Dict) = var, Set(), Set()
evaluate_(var::UnitRange, ::Dict) = var, Set(), Set()
function evaluate_(var::Symbol, env::Dict)
    value = haskey(env, var) ? env[var] : var
    @assert !ismissing(value) "Scalar variables in data can't be missing, but $var given as missing"
    return ismissing(value) ? var : value, Set(), Set()
end 
function evaluate_(var::Expr, env::Dict)
    deps, args = Set(), Set()
    if Meta.isexpr(var, :ref)
        idxs = []
        for i in 2:length(var.args)
            e, d, a = evaluate_(var.args[i], env)
            push!(idxs, e); union!(deps, d); union!(args, a)
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
        elseif all(x -> x isa Union{Number, UnitRange}, idxs)
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
            i isa Symbol && (push!(deps, i); push!(args, i))
        end
        push!(args, (var.args[1], ()))
        push!(deps, (var.args[1], ()))
        return Expr(var.head, var.args[1], idxs...), deps, args
    else # function call
        fun_args = []
        for i in 2:length(var.args)
            e, d, a = evaluate_(var.args[i], env)
            push!(fun_args, e); union!(deps, d); union!(args, a)
        end

        for a in fun_args
            a isa Symbol && (push!(deps, a); push!(args, a))
        end

        try
            return eval(Expr(var.head, var.args[1], fun_args...)), deps, args
        catch _
            return Expr(var.head, var.args[1], fun_args...), deps, args
        end
    end
end

"""
    constprop(x, env)

Constant propagation for `x` in the environment `env`. Return the constant propagated expression.
"""
function constprop(x, env)
    try_constprop = _constprop(x, env)
    while try_constprop != x
        x = try_constprop
        try_constprop = _constprop(x, env)
    end
    return x
end

_constprop(x::Number, env) = x
_constprop(x::Symbol, env) = haskey(env, x) ? env[x] : x
function _constprop(x, env)
    x = deepcopy(x)
    for i in 2:length(x.args)
        if Meta.isexpr(x.args[i], :ref) && all(x -> x isa Number, x.args[i].args[2:end]) && haskey(env, x.args[i].args[1])
            val = env[x.args[i].args[1]][x.args[i].args[2:end]...]
            x.args[i] = ismissing(val) ? x.args[i] : val
        else
            x.args[i] = _constprop(x.args[i], env)
        end
    end
    return x
end

"""
    concretize_colon(expr, array_sizes)

Replace all `Colon()`s in `expr` with the corresponding array size.

# Examples

```jldoctest
julia> JuliaBUGS.concretize_colon(:(f(x[1, :])), Dict(:x => [2, 3]))
:(f(x[1, 3]))
```
"""
function concretize_colon_indexing(expr::Expr, array_sizes) 
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, x_[idx__])
            for i in 1:length(idx)
                if idx[i] == :(:)
                    idx[i] = Expr(:call, :(:), 1, array_sizes[x][i])
                end
            end
            return Expr(:ref, x, idx...)
        end
        return sub_expr
    end
end

function create_array_var(n, array_sizes, env)
    if haskey(array_sizes, n)
        return Var(n, Tuple([1:s for s in array_sizes[n]]))
    else
        @assert haskey(env, n)
        @assert env[n] isa Union{Array{Union{Missing, Float64}}, Array{Union{Missing, Int64}}}
        return Var(n, Tuple([1:i for i in size(env[n])]))      
    end
end

try_cast_to_int(x::Integer) = x
try_cast_to_int(x::Real) = Int(x)
try_cast_to_int(x) = x # catch other types, e.g. UnitRange, Colon

# TODO: can merge transformed_variables with data to get env, require to know what are transformed variables, and what are second-order constant propagations
function assignment!(pass::NodeFunctions, expr::Expr, env::Dict)
    lhs_expr, rhs_expr = expr.args[1:2]
    var_type = Meta.isexpr(expr, :(=)) ? Logical : Stochastic

    link_function = Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[1] : identity
    lhs_var = find_variables_on_lhs(Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[2] : lhs_expr, env)
    
    rhs_expr = concretize_colon_indexing(rhs_expr, pass.array_sizes)
    rhs = evaluate(rhs_expr, env)
    var_type == Logical && rhs isa Union{Number, Array{<:Number}} && return

    if rhs isa Symbol
        @assert lhs isa Union{Scalar, ArrayElement}
        node_function = :identity
        node_args = [Var(rhs)]
        dependencies = [Var(rhs)]
    elseif Meta.isexpr(rhs, :ref) && all(x -> x isa Union{Number, UnitRange}, rhs.args[2:end])
        @assert var_type == Logical # if rhs is a variable, then the expression must be logical
        rhs_var = Var(rhs.args[1], Tuple(rhs.args[2:end]))
        rhs_array_var = create_array_var(rhs_var.name, pass.array_sizes, env)
        size(rhs_var) == size(lhs_var) || error("Size mismatch between lhs and rhs at expression $expr")
        if lhs_var isa ArrayElement
            @assert pass.array_bitmap[rhs_var.name][rhs_var.indices...] "Variable $rhs_var is not defined."
            node_function = MacroTools.@q ($(rhs_var.name)::Array) -> $(rhs_var.name)[$(rhs_var.indices...)]
            node_args = [rhs_array_var]
            dependencies = [rhs_var]
        else
            # rhs is not evaluated into a concrete value, then at least some elements of the rhs array are not data
            non_data_vars = filter(x -> x isa Var, evaluate(rhs, env))
            for v in non_data_vars
                @assert pass.array_bitmap[v.name][v.indices...] "Variable $v is not defined."
            end
            node_function = MacroTools.@q ($(rhs_var.name)::Array) -> $(rhs_var.name)[$(rhs_var.indices...)]
            node_args = [rhs_array_var]
            dependencies = non_data_vars
        end
    else
        rhs_expr = constprop(rhs_expr, env)
        _, dependencies, node_args = evaluate_(rhs_expr, env)

        dependencies, node_args = map(
            x -> map(x) do x_elem
                if x_elem isa Symbol
                    return Var(x_elem)
                elseif x_elem isa Tuple && last(x_elem) == ()
                    return create_array_var(first(x_elem), pass.array_sizes, env)
                else
                    return Var(first(x_elem), last(x_elem))
                end
            end, map(collect, (dependencies, node_args))
        )

        rhs_expr = MacroTools.postwalk(rhs_expr) do sub_expr
            if @capture(sub_expr, arr_[idxs__])
                new_idxs = [idx isa Integer ? idx : :(JuliaBUGS.try_cast_to_int($(idx))) for idx in idxs]
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

    pass.link_functions[lhs_var] = link_function
    pass.node_args[lhs_var] = node_args
    pass.node_functions[lhs_var] = node_function
    pass.dependencies[lhs_var] = dependencies
end

function post_process(pass::NodeFunctions, expr, env, vargs...)
    return pass
end
