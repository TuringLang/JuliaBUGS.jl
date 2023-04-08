struct NodeFunctions{VT} <: CompilerPass
    vars::VT
    array_sizes::Dict
    array_bitmap::Dict

    link_functions::Dict
    node_args::Dict
    node_f_exprs::Dict
end

"""
    evaluate_(var, env)

Evaluate `var` in the environment `env`. Return the evaluated value, the set of variables that `var` depends 
on, and the arguments of the node function based on `var`. Assume all Colon indexing has been concretized.

# Examples
julia> evaluate_(:(x[a]), Dict())
(:(x[a]), Set(Any[:a, x[]]), Set(Any[:a, x[]]))

julia> evaluate_(:(x[a]), Dict(:a => 1))
(:(x[1]), Set(Any[x[1]]), Set(Any[x[]]))

julia> evaluate_(:(x[y[1]+1]+a+1), Dict())
(:(x[y[1] + 1] + a + 1), Set(Any[:a, y[1], x[]]), Set(Any[:a, y[], x[]]))

julia> evaluate_(:(getindex(x[1:2, 1:3], a, b)), Dict(:x => [1 2 3; 4 5 6]))
(:(getindex([1 2 3; 4 5 6], a, b)), Set(Any[:a, :b]), Set(Any[:a, :b, x[]]))

julia> evaluate_(:(getindex(x[1:2, 1:3], a, b)), Dict(:x => [1 2 missing; 4 5 6]))
(:(getindex(Union{Missing, Int64}[1 2 missing; 4 5 6], a, b)), Set(Any[:a, :b, x[1, 3]]), Set(Any[:a, :b, x[]]))
```
"""
evaluate_(var::Number, ::Dict) = var, Set(), Set()
evaluate_(var::UnitRange, ::Dict) = var, Set(), Set()
evaluate_(var::Symbol, env::Dict) = haskey(env, var) ? env[var] : var, Set(), Set()
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
                return env[var.args[1]][idxs...], deps, args
            else # then it's a variable
                push!(deps, ArrayElement(var.args[1], Tuple(idxs))) # add the variable for fine-grain dependency
                push!(args, ArrayVar(var.args[1], ())) # add the corresponding array variable for node function arguments
                return Expr(var.head, var.args[1], idxs...), deps, args
            end
        elseif all(x -> x isa Union{Number, UnitRange}, idxs)
            if haskey(env, var.args[1])
                value = getindex(env[var.args[1]], idxs...)
                if any(ismissing, value)
                    missing_idxs = findall(ismissing, value)
                    for idx in missing_idxs
                        push!(deps, ArrayElement(var.args[1], Tuple(idx)))
                    end
                end
                push!(args, ArrayVar(var.args[1], ()))
                return value, deps, args
            else
                push!(deps, ArrayElement(var.args[1], Tuple(idxs)))
                push!(args, ArrayVar(var.args[1], ()))
                return Expr(var.head, var.args[1], idxs...), deps, args
            end
        end

        for i in idxs # if an index is a Symbol, then it's a variable
            i isa Symbol && (push!(deps, i); push!(args, i))
        end
        push!(args, ArrayVar(var.args[1], ()))
        push!(deps, ArrayVar(var.args[1], ()))
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
constprop(x::Number, env) = x
constprop(x::Symbol, env) = haskey(env, x) ? env[x] : x
function constprop(x, env)
    for i in 2:length(x.args)
        if Meta.isexpr(x.args[i], :ref) && all(x -> x isa Number, x.args[i].args[2:end]) && haskey(env, x.args[i].args[1])
            x.args[i] = env[x.args[i].args[1]][x.args[i].args[2:end]...]
        else
            x.args[i] = constprop(x.args[i], env)
        end
    end
    return x
end

try_case_to_int(x::Integer) = x
try_case_to_int(x::AbstractFloat) = isinteger(x) ? Int(x) : x

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

@inline create_array_var(n, array_sizes) = Var(n, Tuple([1:s for s in array_sizes[s]]))

# TODO: can merge transformed_variables with data to get env, require to know what are transformed variables, and what are second-order constant propagations
function assignment!(pass::NodeFunctions, expr::Expr, env::Dict)
    lhs_expr, rhs_expr = expr.args[1:2]
    var_type = Meta.isexpr(expr, :(=)) ? Logical : Stochastic

    link_function = Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[1] : identity
    lhs_var = find_variables_on_lhs(Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[2] : lhs_expr, env)
    
    rhs_expr = concretize_colon_indexing(rhs_expr, pass.array_sizes)
    rhs = evaluate(rhs_expr, env)
    rhs isa Union{Number, Array{<:Number}} && return

    if rhs isa Symbol
        @assert lhs isa Union{Scalar, ArrayElement}
        node_function = :identity
        node_args = [Var(rhs)]
    elseif Meta.isexpr(rhs, :ref) && all(x -> x isa Union{Number, UnitRange}, rhs.args[2:end])
        rhs_var = Var(rhs.args[1], Tuple(rhs.args[2:end]))
        rhs_array_var = create_array_var(rhs_var.name, pass.array_sizes)
        size(rhs_var) == size(lhs_var) || error("Size mismatch between lhs and rhs at expression $expr")
        if lhs_var isa ArrayElement
            node_function = :identity
            node_args = [lhs_var]
            dependencies = [rhs_var]
        else
            # rhs is not evaluated into a concrete value, then at least some elements of the rhs array are not data
            non_data_vars = filter(x -> x isa Var, evaluate(rhs, env))
            for v in non_data_vars
                @assert pass.array_bitmap[v.name][v.indices...] "Variable $v is not defined."
            end
            # fine-grain dependency is guaranteed
            # TODO: if Stochastic, rhs has to be the same type
            # if Logical, rhs can have missing values, node function probably should be finer grained 
            node_function = MacroTools.@q function $(Symbol(lhs))($(rhs_var.name))
                return $(rhs_var.name)[$(rhs_var.indices...)]
            end
            node_args = [rhs_array_var]
            dependencies = non_data_vars
        end
    else
        if isa(rhs, Distributions.Distribution) #TODO: need range to be evaluated, fix this
            rhs = rhs_expr
        end
        replaced_expr = replace_vars(evaluated_expr, array_map, env)

        #TODO: add type signature to args
        args = Dict()
        gen_expr = MacroTools.postwalk(replaced_expr) do sub_expr
            if sub_expr isa Var
                gen_arg = Symbol(sub_expr)
                args[sub_expr] = gen_arg
                return gen_arg
            elseif sub_expr isa Array{Var}
                gen_arg = Symbol.(sub_expr)
                for (i, v) in enumerate(sub_expr)
                    args[v] = gen_arg[i]
                end
                return Expr(:call, :reshape, Expr(:vect, gen_arg...), (size(sub_expr)...))
            else
                return sub_expr
            end
        end

        gen_expr = getindex_to_ref(gen_expr)
        gen_expr = MacroTools.postwalk(gen_expr) do sub_expr
            if @capture(sub_expr, arr_[idxs__])
                new_idxs = [:(try_case_to_int($(idx))) for idx in idxs] # TODO: for now, we just cast to integer, but we should check if the index is an integer
                return Expr(:ref, arr, new_idxs...)
            else
                return sub_expr
            end
        end

        f_expr = MacroTools.postwalk(
            MacroTools.unblock,
            MacroTools.combinedef(
                Dict(
                    :args => values(args),
                    :body => gen_expr,
                    :kwargs => Any[],
                    :whereparams => Any[],
                ),
            ),
        )

        r_func, r_var_args = f_expr, keys(args)
    end

    pass.link_functions[rhs] = link_function
    if expr.head == :(=)
        @assert !in(rhs, keys(pass.logical_node_args)) "Repeated assignment to $rhs"
        pass.logical_node_args[rhs] = r_var_args
        pass.logical_node_f_exprs[rhs] = r_func
    else
        @assert expr.head == :(~)
        pass.stochastic_node_args[rhs] = r_var_args
        pass.stochastic_node_f_exprs[rhs] = r_func
    end
    return nothing
end

function post_process(pass::NodeFunctions)
    data = pass.data
    vars = pass.vars
    array_map = pass.array_map
    missing_elements = pass.missing_elements
    logical_node_args = pass.logical_node_args
    logical_node_f_exprs = pass.logical_node_f_exprs
    stochastic_node_args = pass.stochastic_node_args
    stochastic_node_f_exprs = pass.stochastic_node_f_exprs
    link_functions = pass.link_functions

    array_variables = []
    for var in keys(vars)
        if !haskey(logical_node_args, var) && !haskey(stochastic_node_args, var) # variables without node functions
            @assert isa(var, ArrayElement) || isa(var, ArrayVariable)
            if var isa ArrayElement
                # then come from either ArrayVariable or ArraySlice
                source_var = filter(
                    x -> (x isa ArrayVariable || x isa ArraySlice) && x.name == var.name,
                    vcat(
                        map(
                            collect, [keys(logical_node_args), keys(stochastic_node_args)]
                        )...,
                    ),
                )
                @assert length(source_var) == 1
                array_var = first(source_var)
                logical_node_args[var] = [array_var]
                logical_node_f_exprs[var] = MacroTools.postwalk(
                    MacroTools.rmlines, :((array_var) -> array_var[$(var.indices...)])
                )
            elseif var.name in keys(array_map)
                push!(array_variables, var)
                array_elems = scalarize(var)
                logical_node_args[var] = vcat(array_elems)
                # @assert all(x -> x in keys(node_args), array_elems) # might not be true
                # arg_list = [Symbol("arg" * string(i)) for i in 1:length(array_elems)]
                f_name = Symbol("compose_" * String(Symbol(var)))
                # logical_node_f_exprs[var] = MacroTools.postwalk(
                #     MacroTools.rmlines,
                #     :(function ($f_name)($(arg_list...))
                #         args = [$(arg_list...)]
                #         return reshape(collect(args), $(size(array_map[var.name])))
                #     end),
                # )
                logical_node_f_exprs[var] = MacroTools.postwalk(
                    MacroTools.rmlines,
                    :(function ($f_name)(args::Vector)
                        return reshape(args, $(size(array_map[var.name])))
                    end),
                )
            else # data array
                # TODO: for now, handle this in logdensityproblems, this is a leak of abstraction, need to be addressed
            end
        end
    end

    for v in vcat(collect(values(missing_elements))...)
        logical_node_args[v] = []
        logical_node_f_exprs[v] = :missing
    end

    return logical_node_args,
    logical_node_f_exprs, stochastic_node_args, stochastic_node_f_exprs, link_functions,
    array_variables
end
