struct NodeFunctions <: CompilerPass
    array_map
    node_args::Dict
    node_functions::Dict
    node_function_cache::Dict
    evaled_func_cache::Dict
end

NodeFunctions() = NodeFunctions(Dict(), Dict(), Dict(), Dict(), Dict())

lhs(::NodeFunctions, expr, env::Dict) = find_variables_on_lhs(expr, env)

function rhs(pass::NodeFunctions, expr::Expr, env::Dict, array_map)
    evaluated_expr = eval(expr, env)
    if evaluated_expr isa Distributions.Distribution
        dist_func = nameof(typeof(evaluated_expr))
        if dist_func == :GenericMvTDist
            dist_func = :MvTDist
        elseif dist_func == :DiscreteNonParametric
            dist_func = :Categorical
        end
        f_expr = Expr(:call, dist_func, Distributions.params(evaluated_expr)...)
        return Expr(:(->), :(()), f_expr), []
    end
    evaluated_expr isa Number && return :(() -> $evaluated_expr), []
    evaluated_expr isa Symbol && return :(identity), [Var(evaluated_expr)]
    if Meta.isexpr(evaluated_expr, :ref) &&
        all(x -> x isa Number || x isa UnitRange, evaluated_expr.args[2:end])
        return identity, [Var(evaluated_expr.args[1], evaluated_expr.args[2:end])]
    end

    replaced_expr = replace_vars(evaluated_expr, array_map)
    args = Dict()
    gen_expr = MacroTools.postwalk(replaced_expr) do sub_expr
        if sub_expr isa Var
            gen_arg = gensym(:arg)
            args[sub_expr] = gen_arg
            return gen_arg
        else
            return sub_expr
        end
    end

    haskey(pass.node_function_cache, expr) &&
        return pass.node_function_cache[expr], keys(args)

    f_expr = MacroTools.unblock(
        MacroTools.combinedef(
            Dict(
                :args => values(args),
                :body => gen_expr,
                :kwargs => Any[],
                :whereparams => Any[],
            ),
        ),
    )
    pass.node_function_cache[expr] = f_expr

    return f_expr, keys(args)
end

function replace_vars(expr, array_map)
    return varify_arrayvars(ref_to_getindex(varify_arrayelems(varify_scalars(expr))), array_map)
end

function varify_scalars(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, f_(args__))
            for (i, arg) in enumerate(args)
                if arg isa Symbol
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

function varify_arrayvars(expr, array_map)
    return MacroTools.postwalk(expr) do sub_expr
        @assert !Meta.isexpr(sub_expr, :ref)
        if MacroTools.@capture(sub_expr, f_(args__))
            if f == :getindex
                args[1] = Var(args[1], array_map)
            end
            for (i, arg) in enumerate(args)
                args[i] = varify_arrayvars(arg, array_map)
            end
            return Expr(:call, f, args...)
        else
            return sub_expr
        end
    end
end

function assignment!(pass::NodeFunctions, expr::Expr, env::Dict)
    array_map = pass.array_map
    l_var = lhs(pass, expr.args[1], env)
    @assert l_var isa Var
    r_func, r_var_args = rhs(pass, expr.args[2], env, array_map)

    if haskey(pass.evaled_func_cache, expr)
        evaled_func = pass.evaled_func_cache[expr]
    else
        evaled_func = eval(r_func)
        pass.evaled_func_cache[expr] = evaled_func
    end

    if l_var in keys(pass.node_args)
        @assert pass.node_args[l_var] == r_var_args
        @assert pass.node_functions[l_var] == r_func
    else
        pass.node_args[l_var] = r_var_args
        pass.node_functions[l_var] = evaled_func
    end
end

function post_process(pass::NodeFunctions)
    return pass.node_args, pass.node_functions
end
