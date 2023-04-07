struct NodeFunctions{VT} <: CompilerPass
    vars::VT
    array_sizes::Dict
    array_bitmap::Dict

    link_functions::Dict
    node_args::Dict
    node_f_exprs::Dict
end

# Generate an expression to reconstruct a given distribution object
function toexpr(dist::Distributions.Distribution)
    dist_type = typeof(dist)
    dist_params = params(dist)
    return Expr(:call, dist_type, dist_params...)
end

function getindex_to_ref(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :call) && sub_expr.args[1] == :getindex
            return Expr(:ref, sub_expr.args[2:end]...)
        else
            return sub_expr
        end
    end
end

"""
    varify_scalars(expr)

Convert all symbols in `expr` to `Var`s.

# Examples

```jldoctest
julia> expr = :(a + b + c) |> dump
Expr
  head: Symbol call
  args: Array{Any}((4,))
    1: Symbol +
    2: ArrayElement{0}
      name: Symbol a
      indices: Tuple{} ()
    3: ArrayElement{0}
      name: Symbol b
      indices: Tuple{} ()
    4: ArrayElement{0}
      name: Symbol c
      indices: Tuple{} ()
```
"""
function varify_scalars(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            for (i, arg) in enumerate(args)
                if arg isa Symbol && arg != :nothing
                    args[i] = Var(arg)
                else
                    args[i] = varify_scalars(arg)
                end
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end

"""
    varify_arrayelems(expr)

Convert all array elements in `expr` to `Var`s.

# Examples

```jldoctest
julia> expr = JuliaBUGS.eval(:(a[1, 2] + b[1, 1:2]), Dict());

julia> varify_arrayelems(expr) # b[1, 1:2] is scalarized
:(a[1, 2] + Var[b[1, 1], b[1, 2]])
```
"""
function varify_arrayelems(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            for (i, arg) in enumerate(args)
                if Meta.isexpr(arg, :ref) && all(x -> x isa Union{Number, UnitRange, Colon}, arg.args[2:end])
                    if all(x -> x isa Number, arg.args[2:end])
                        args[i] = Var(arg.args[1], Tuple(arg.args[2:end]))
                    else
                        args[i] = scalarize(Var(arg.args[1], Tuple(arg.args[2:end])))
                    end
                else
                    args[i] = varify_arrayelems(arg)
                end
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end

"""
    varify_arrayvars(expr)

Convert all array variables in `expr` to `Var`s.

# Examples

```jldoctest
julia> expr = :(x[y[1] + 1] + 1); evaled_expr = JuliaBUGS.eval(expr, Dict());

julia> part_var_expr = varify_arrayelems(varify_scalars(evaled_expr));

julia> varify_arrayvars(ref_to_getindex(part_var_expr)) |> dump
:(getindex(x[Colon()], y[1] + 1) + 1)
'''
"""
function varify_arrayvars(expr)
    return MacroTools.prewalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            if f == :getindex
                @assert !all(x -> x isa Union{Number, UnitRange, Colon}, args[2:end])
                # @assert !isa(args[1], Var) # postwalk may revisit the same code 
                args[1] isa Var || (args[1] = Var(args[1], Tuple([Colon() for i in 1:length(args)-1])))
            end
            for (i, arg) in enumerate(args)
                if arg isa Var || arg == Colon()
                    continue
                end
                args[i] = varify_arrayvars(arg)
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end

try_case_to_int(x::Integer) = x
try_case_to_int(x::AbstractFloat) = isinteger(x) ? Int(x) : x

# by substituting all the variables in an expression with `Var`s, later we can filter out the variables
function replace_vars(expr)
    return varify_arrayvars(ref_to_getindex(varify_arrayelems(varify_scalars(expr))))
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
function concretize_colon(expr::Expr, array_sizes) 
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, x_[idx__])
            for i in 1:length(idx)
                if idx[i] == :(:)
                    idx[i] = array_sizes[x][i]
                end
            end
            return Expr(:ref, x, idx...)
        end
        return sub_expr
    end
end

# TODO: can merge transformed_variables with data to get env, require to know what are transformed variables, and what are second-order constant propagations
function assignment!(pass::NodeFunctions, expr::Expr, env::Dict)
    lhs_expr, rhs_expr = expr.args[1:2]
    var_type = Meta.isexpr(expr, :(=)) ? Logical : Stochastic

    link_function = Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[1] : identity
    lhs_var = find_variables_on_lhs(Meta.isexpr(lhs_expr, :call) ? lhs_expr.args[2] : lhs_expr, env)
    
    rhs = eval(concretize_colon(rhs_expr, pass.array_sizes), env)
    rhs isa Union{Number, Array{<:Number}} && return

    if rhs isa Symbol
        @assert lhs isa Union{Scalar, ArrayElement}
        node_function = :identity
        node_args = [Var(rhs)]
    elseif Meta.isexpr(rhs, :ref) && all(x -> x isa Union{Number, UnitRange}, rhs.args[2:end])
        rhs_var = Var(rhs.args[1], Tuple(rhs.args[2:end]))
        rhs_array_var = Var(rhs.args[1], Tuple(pass.array_sizes[rhs.args[1]]))
        size(rhs_var) == size(lhs_var) || error("Size mismatch between lhs and rhs at expression $expr")
        if lhs_var isa ArrayElement
            node_function = :identity
            node_args = [lhs_var]
            dependencies = [rhs_var]
        else
            # rhs is not evaluated into a concrete value, then at least some elements of the rhs array are not data
            evaled_rhs_var = eval_var(rhs, env)
            non_data_vars = filter(x -> x isa Var, rhs)
            for v in non_data_vars
                @assert pass.array_bitmap[v.name][v.indices...] "Variable $v is not defined."
            end
            # fine-grain dependency is guaranteed
            node_function = MacroTools.@q function $(Symbol(lhs))($(rhs_var.name))
                return $(rhs_var.name)[$(rhs_var.indices...)]
            end
            node_args = [rhs_array_var]
            dependencies = non_data_vars
        end
    elseif isa(rhs, Distributions.Distribution)
        node_function = Expr(rhs_expr.head, rhs_expr.args[1], map(ex -> eval(ex, env), rhs_expr.args[2:end])...)
        node_args = []
        dependencies = []
    else
        replaced_expr = replace_vars(evaluated_expr, array_map, env)

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
