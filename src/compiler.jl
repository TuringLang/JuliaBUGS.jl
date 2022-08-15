using Distributions
using AbstractPPL.GraphPPL: Model
using Symbolics
using Random
using MacroTools
using LinearAlgebra
using BugsModels

##

##
function analyze_data!(data::Union{Dict, NamedTuple}, rules, arrays)
    for (key, value) in data
        if isa(value, Number)
            rules[get_sym_var(key)] = value
        elseif isa(value, Array)
            sym_array = create_sym_array(key, collect(size(value)))            
            for i in eachindex(value)
                rules[sym_array[i]] = value[i]
            end
            arrays[key] = sym_array
        else
            error("Value type not supported.")
        end
    end
end

# This function comes from `@macroexpand @variable some_variable`. Doing this to avoid local variable binding.
get_sym_var(var_name::Symbol) = (identity)((Symbolics.wrap)((SymbolicUtils.setmetadata)((SymbolicUtils.Sym){Real}(var_name), Symbolics.VariableSource, (:variables, var_name))))

function create_sym_array(name, size)
    sym_array = Array{Num}(undef, size...)
    for i in CartesianIndices(sym_array)
        sym_array[i] = get_sym_var(Symbol("$(name)"*"[$(collect(Tuple(i))...)]"))
    end
    return sym_array
end

function unroll_for_loops!(expr, rules)
    # flag to signal if unrolling happened
    unrolled_flag = false
    while has_for_loop(expr, rules)
        for i in eachindex(expr.args)
            arg = expr.args[i]
            if arg.head == :for          
                unrolled = unroll_for_loop(arg, rules)
                splice!(expr.args, i, unrolled.args)
                unrolled_flag = true
            end
        end
    end
    return unrolled_flag
end

function has_for_loop(expr, rules)
    for arg in expr.args
        if arg.head == :for
            lower_bound, higher_bound = arg.args[1].args[2].args 
            lower_bound = resolve(lower_bound, rules)
            higher_bound = resolve(higher_bound, rules)
            if isa(lower_bound, Integer) && isa(higher_bound, Integer)
                return true
            end
        end
    end
    return false
end

function unroll_for_loop(expr, rules)
    loop_var = expr.args[1].args[1]
    lower_bound, higher_bound = expr.args[1].args[2].args
    body = expr.args[2]

    unrolled_exprs = []
    lower_bound = resolve(lower_bound, rules)
    higher_bound = resolve(higher_bound, rules)
    if isa(lower_bound, Integer) || isa(higher_bound, Integer)
        for i in lower_bound:higher_bound
            sub_expr = replace_sym_with_num(body, loop_var, i)
            push!(unrolled_exprs, sub_expr.args...)
        end
        return Expr(:block, unrolled_exprs...)
    elseif isa(lower_bound, AbstractFloat) || isa(higher_bound, AbstractFloat)
        error("Loop bounds need to be integers.")
    else
        # if loop bounds contain variables that can't be partial evaluated at this moment
        return expr
    end
end

function replace_sym_with_num(expr, pre::Symbol, post::Number)
    MacroTools.prewalk(expr) do sub_expr
        if isa(sub_expr, Symbol) && sub_expr == pre
            return post
        end
        return sub_expr
    end
end

function resolve(variable, rules)
    if isa(variable, Union{Integer, AbstractFloat}) 
        return variable
    else 
        if !isa(variable, Num)
            variable = get_sym_var(variable)
        end
        resolved_variable = evaluate_sym_var(variable, rules)
        return Symbolics.unwrap(resolved_variable)
    end
end

function evaluate_sym_var(variable, rules)
    evaluated = Symbolics.substitute(variable, rules)
    try_evaluated = Symbolics.substitute(evaluated, rules)
    
    while true
        Symbolics.isequal(evaluated, try_evaluated) && break
        evaluated = try_evaluated
        try_evaluated = Symbolics.substitute(try_evaluated, rules)
    end
    
    return try_evaluated
end

function resolve_ref_obj!(expr, arrays)
    num_dims = length(expr.args) - 1
    array_name = expr.args[1]
    index = expr.args[2:end]

    # if array not exist
    if !haskey(arrays, array_name)
        sym_array = create_sym_array(array_name, index)
        arrays[array_name] = sym_array
        return sym_array[index...]
    end

    # if array exists
    sym_array = arrays[array_name]
    # check if dimension match
    if ndims(sym_array) == num_dims
        old_size = size(sym_array)
        if all([index[i] <= old_size[i] for i in eachindex(index)])
            return sym_array[index...]
        
        else
            # expand the array
            new_size = collect(size(sym_array))
            for i in eachindex(index)
                if index[i] > old_size[i]
                    new_size[i] = index[i]
                end
            end

            new_array = Array{Num}(undef, new_size...)
            for i in CartesianIndices(new_array)
                new_array[i] = get_sym_var(Symbol("$array_name"*"$(collect(Tuple(i)))"))
            end
            
            arrays[array_name] = new_array
            return new_array[index...] # again need to handle indexing later
        end
    end

    error("Dimension doesn't match!")
end

function parse_logical_assignments!(expr, arrays, rules)
    for arg in expr.args
        if arg.head == :(=)
            lhs, rhs = arg.args

            # replace refs with symbolic variables
            # LHS should be simple, i.e. ref, variable or link function
            !isa(lhs, Symbol) || !MacroTools.isexpr(lhs, ref) || error("LHS need to be simple.")
            if MacroTools.isexpr(lhs, :ref)
                lhs = Symbolics.tosymbol(resolve_ref_obj!(lhs, arrays))
            end
            
            ref_sym_variables = []
            rhs = MacroTools.prewalk(rhs) do sub_expr
                if MacroTools.isexpr(sub_expr, :ref)
                    sym_var = resolve_ref_obj!(sub_expr, arrays)
                    push!(ref_sym_variables, sym_var)
                    return Symbolics.tosymbol(sym_var)
                else
                    return sub_expr
                end
            end

            variables = find_variables(rhs)
            
            sym_rhs = create_sym_rhs(rhs, ref_sym_variables, variables)
            sym_lhs = get_sym_var(lhs)
            if haskey(rules, sym_lhs) 
                error("Repeated definition for $(lhs)") 
            end
            rules[get_sym_var(lhs)] = sym_rhs
        end
    end
end

function handle_link_functions!(expr) end

function create_sym_rhs(rhs, ref_sym_variables, variables)
    # bind symbolic variables to local variable with same names
    # so that when eval creates a symbolic expression 
    eval(create_local_binding_exprs(ref_sym_variables))
    eval(create_local_binding_exprs(variables))
    return eval(rhs)
end

function create_local_binding_exprs(sym_vars)
    ret_expr = []
    for sym_var in sym_vars
        assignment_expr = Expr(:(=), Symbolics.tosymbol(sym_var),  sym_var)
        push!(ret_expr, assignment_expr) 
    end
    return Expr(:block, ret_expr...)
end

# Find all the variables(Symbol) in expr
function find_variables(rhs)
    variables = []
    recursive_find_variables!(rhs, variables)
    return map(get_sym_var, variables)
end

function recursive_find_variables!(expr, leaves)
    MacroTools.prewalk(expr) do sub_expr
        if MacroTools.isexpr(sub_expr, :call)
            for _arg in sub_expr.args[2:end]
                if isa(_arg, Symbol) 
                    # filter out the variables turned from ref objects
                    if !Base.occursin("[", string(_arg)) 
                        push!(leaves, _arg)
                    end
                else 
                    recursive_find_variables!(_arg, leaves)
                end
            end
        end
    end
end
##

# """
# Top level function
# """
# function compile_graph(; model_def, data)    
#     model_def = BugsModels.@bugsast(model_def)

#     # Used to store all the arrays of symbolic variables
#     arrays = Dict()
#     # Store all the logical assignment for symbolics variables for partial evaluation
#     rules = Dict()
    
#     # Pass #1, handle input data
#     analyze_data!(data, rules, arrays)
    
#     # Alternate Unrolling and Parse logical assignments 
    
#     ## NOT FINISHED
    

#     return copmile_graph_from_bugsast(bugsast, data)
# end

##