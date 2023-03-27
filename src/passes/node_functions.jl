struct NodeFunctions <: CompilerPass
    vars::Vars
    array_map::Dict{}
    missing_elements::Dict
    link_functions::Dict
    logical_node_args::Dict
    logical_node_f_exprs::Dict
    stochastic_node_args::Dict
    stochastic_node_f_exprs::Dict
end

function NodeFunctions(vars, array_map, missing_elements)
    return NodeFunctions(vars, array_map, missing_elements, Dict(), Dict(), Dict(), Dict(), Dict())
end

function lhs(::NodeFunctions, expr::Expr, env::Dict)
    if Meta.isexpr(expr, :call)
        @assert length(expr.args) == 2
        return find_variables_on_lhs(expr.args[2], env), expr.args[1]
    end
    return find_variables_on_lhs(expr, env), nothing
end
lhs(::NodeFunctions, expr, env::Dict) = find_variables_on_lhs(expr, env), nothing

function rhs(pass::NodeFunctions, expr, env::Dict)
    array_map = pass.array_map
    evaluated_expr = eval(expr, env)
    evaluated_expr isa Number && return evaluated_expr, []
    evaluated_expr isa Symbol && return :identity, [Var(evaluated_expr)]
    if Meta.isexpr(evaluated_expr, :ref) &&
        all(x -> x isa Number || x isa UnitRange, evaluated_expr.args[2:end])
        return :identity, [Var(evaluated_expr.args[1], evaluated_expr.args[2:end])]
    end

    replaced_expr = replace_vars(evaluated_expr, array_map)
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

    return f_expr, keys(args)
end

function replace_vars(expr, array_map)
    return varify_arrayvars(
        ref_to_getindex(varify_arrayelems(varify_scalars(expr))), array_map
    )
end

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

function varify_arrayelems(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            for (i, arg) in enumerate(args)
                if Meta.isexpr(arg, :ref) &&
                    all(x -> x isa Number || x isa UnitRange, arg.args[2:end])
                    if all(x -> x isa Number, arg.args[2:end])
                        args[i] = Var(arg.args[1], arg.args[2:end])
                    else
                        args[i] = scalarize(Var(arg.args[1], arg.args[2:end]))
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

function ref_to_getindex(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :ref)
            return Expr(:call, :getindex, sub_expr.args...)
        else
            return sub_expr
        end
    end
end

function varify_arrayvars(expr, array_map)
    return MacroTools.postwalk(expr) do sub_expr
        @assert !Meta.isexpr(sub_expr, :ref)
        if MacroTools.@capture(sub_expr, f_(args__))
            if f == :getindex
                if !isa(args[1], Var)
                    if haskey(array_map, args[1])
                        array_size = collect(size(array_map[args[1]]))
                        array_size = map(x -> 1:x, array_size)
                        args[1] = Var(args[1], array_size)
                    else
                        @warn("Array $(args[1]) should be data array.")
                    end
                end
            end
            for (i, arg) in enumerate(args)
                if arg isa Var || arg == Colon()
                    continue
                end
                args[i] = varify_arrayvars(arg, array_map)
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end

function assignment!(pass::NodeFunctions, expr::Expr, env::Dict)
    l_var, link_func = lhs(pass, expr.args[1], env)
    @assert l_var isa Var
    if !isnothing(link_func)
        pass.link_functions[l_var] = link_func
    end
    r_func, r_var_args = rhs(pass, expr.args[2], env)

    if expr.head == :(=)
        @assert !in(l_var, keys(pass.logical_node_args)) "Repeated assignment to $l_var"
        pass.logical_node_args[l_var] = r_var_args
        pass.logical_node_f_exprs[l_var] = r_func
    else
        @assert expr.head == :(~)
        pass.stochastic_node_args[l_var] = r_var_args
        pass.stochastic_node_f_exprs[l_var] = r_func
    end
    return nothing
end

function post_process(pass::NodeFunctions)

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
        if !haskey(logical_node_args, var) && !haskey(stochastic_node_args, var)
            @assert isa(var, ArrayElement) || isa(var, ArrayVariable)
            if var isa ArrayElement
                # then come from either ArrayVariable or ArraySlice
                source_var = filter(
                    x -> (x isa ArrayVariable || x isa ArraySlice) && x.name == var.name,
                    vcat(map(collect, [keys(logical_node_args), keys(stochastic_node_args)])...),
                )
                @assert length(source_var) == 1
                array_var = first(source_var)
                logical_node_args[var] = [array_var]
                logical_node_f_exprs[var] = MacroTools.postwalk(
                    MacroTools.rmlines, :((array_var) -> array_var[$(var.indices...)])
                )
            else
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
            end
        end
    end 

    for v in vcat(collect(values(missing_elements))...)
        logical_node_args[v] = []
        logical_node_f_exprs[v] = :missing
    end

    return logical_node_args, logical_node_f_exprs, stochastic_node_args, stochastic_node_f_exprs, link_functions, array_variables
end
