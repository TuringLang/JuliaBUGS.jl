struct NodeFunctions <: CompilerPass
    node_args::Dict
    node_functions::Dict
end

NodeFunctions() = NodeFunctions(Dict(), Dict())

lhs(::NodeFunctions, expr::Symbol, env::Dict) = Var(expr)
function lhs(::NodeFunctions, expr::Expr, env::Dict) 
    @assert Meta.isexpr(expr, :ref) "Only symbol or array indexing is allowed on lhs."
    idxs = map(x -> eval(x, env), expr.args[2:end])
    @assert all(x -> x isa Number || x isa UnitRange, idxs) "Only number or range indexing is allowed on lhs."
    return Var(expr.args[1], idxs)
end

function rhs(pass::NodeFunctions, expr::Expr, env::Dict, array_map)
    evaluated_expr = eval(expr, env)
    evaluated_expr isa Distributions.Distribution && return :(() -> $evaluated_expr), []
    evaluated_expr isa Number && return :(() -> $evaluated_expr), []
    evaluated_expr isa Symbol && return :(identity), [Var(evaluated_expr)]
    if Meta.isexpr(evaluated_expr, :ref) && all(x -> x isa Number || x isa UnitRange, evaluated_expr.args[2:end])
        return identity, [Var(evaluated_expr.args[1], evaluated_expr.args[2:end])]
    end
  
    replaced_expr = replace_vars(expr, array_map)
    args = Dict()
    gen_expr = MacroTools.postwalk(replaced_expr) do sub_expr
        if sub_expr isa Var
            gen_arg = Symbol(sub_expr)
            args[sub_expr] = gen_arg
            return gen_arg
        else
            return sub_expr
        end
    end
    
    f_def = Dict(
        :args => values(args),
        :body => gen_expr,
        :kwargs => Any[],
        :whereparams => Any[],
    )

    return MacroTools.combinedef(f_def), keys(args)
end
rhs(::NodeFunctions, expr, env::Dict) = find_variables(expr, env)

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
                if Meta.isexpr(arg, :ref) && all(x -> x isa Number || x isa UnitRange, arg.args[2:end])
                    args[i] = Var(arg.args[1], arg.args[2:end])
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

# require, expr is getindex-ified
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

function assignment!(pass::NodeFunctions, expr::Expr, env::Dict, vargs...)
    array_map = vargs[1]
    l_var = lhs(pass, expr.args[1], env)
    @assert l_var isa Var
    r_func, r_vars = rhs(pass, expr.args[2], env, array_map)

    if l_var in keys(pass.node_args)
        @assert pass.node_args[l_var] == r_vars
        @assert pass.node_functions[l_var] == r_func
    else
        pass.node_args[l_var] = r_vars
        pass.node_functions[l_var] = r_func
    end
end

function post_process(pass::NodeFunctions)
    return pass.node_args, pass.node_functions
end
