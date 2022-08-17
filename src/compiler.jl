using Distributions
using AbstractPPL.GraphPPL: Model
using Symbolics
using Random
using MacroTools
using LinearAlgebra
using BugsModels

function parsedata!(data::Union{Dict, NamedTuple}, rules, arrays)
    for (key, value) in data
        if isa(value, Number)
            rules[tosymbolic(key)] = value
        elseif isa(value, Array)
            sym_array = createsymbolicarray(key, collect(size(value)))            
            for i in eachindex(value)
                rules[sym_array[i]] = value[i]
            end
            arrays[key] = sym_array
        else
            error("Value type not supported.")
        end
    end
end

function createsymbolicarray(name::Symbol, size)
    sym_array = Array{Num}(undef, size...)
    for i in CartesianIndices(sym_array)
        sym_array[i] = tosymbolic(Symbol("$(name)"*"[$(collect(Tuple(i))...)]"))
    end
    return sym_array
end

function unrollforloops!(expr, rules, arrays)
    # flag to signal if unrolling happened
    unrolled_flag = false
    while hasforloop(expr, rules)
        for i in eachindex(expr.args)
            arg = expr.args[i]
            if arg.head == :for          
                unrolled = recursive_unrollforloop(arg, rules, arrays)
                splice!(expr.args, i, unrolled.args)
                unrolled_flag = true
            end
        end
    end
    return unrolled_flag
end

function hasforloop(expr, rules)
    for arg in expr.args
        if arg.head == :for
            lower_bound, higher_bound = arg.args[1].args[2].args 
            lower_bound = resolve(lower_bound, rules, arrays)
            higher_bound = resolve(higher_bound, rules, arrays)
            if isa(lower_bound, Integer) && isa(higher_bound, Integer)
                return true
            end
        end
    end
    return false
end

function recursive_unrollforloop(expr, rules, arrays)
    loop_var = expr.args[1].args[1]
    lower_bound, higher_bound = expr.args[1].args[2].args
    body = expr.args[2]

    lower_bound = resolve(lower_bound, rules, arrays)
    higher_bound = resolve(higher_bound, rules, arrays)
    if isa(lower_bound, Integer) || isa(higher_bound, Integer)  
        unrolled_exprs = []
        for i in lower_bound:higher_bound
            # Replace all the loop variables in array indices with integers
            replaced_expr = MacroTools.postwalk(sub_expr -> isa(sub_expr, Symbol) && sub_expr == loop_var ? i : sub_expr, body)
            push!(unrolled_exprs, replaced_expr.args...)
        end
        return Expr(:block, unrolled_exprs...)
    elseif isa(lower_bound, AbstractFloat) || isa(higher_bound, AbstractFloat)
        error("Loop bounds need to be integers.")
    else
        # if loop bounds contain variables that can't be partial evaluated at this moment
        return expr
    end
end

# This function comes from `@macroexpand @variable some_variable`. Doing this to avoid local variable binding.
tosymbolic(var_name::Symbol) = (identity)((Symbolics.wrap)((SymbolicUtils.setmetadata)((SymbolicUtils.Sym){Real}(var_name), Symbolics.VariableSource, (:variables, var_name))))
tosymbolic(variable::Expr) = MacroTools.isexpr(variable, :ref) && ref_to_symbolic!(variable, arrays)
tosymbolic(variable::Num) = variable

resolve(variable::Union{Integer, AbstractFloat}, rules::Dict, arrays::Dict) = variable
function resolve(variable, rules, arrays)
    resolved_variable = symboliceval(tosymbolic(variable), rules)
    return Symbolics.unwrap(resolved_variable)
end

"""
    Wrapper around `Symbolics.substitute`

    Reason for this function: 
        ```julia
            > substitute(a, Dict(a=>b+c, b=>2, c=>3))
            b + c
        ```
    
    CAUTION: the implementation can cause infinite loop in the general case, but for simple 
    cases it should suffice, improve later
"""
function symboliceval(variable::Num, rules)
    evaluated = Symbolics.substitute(variable, rules)
    try_evaluated = Symbolics.substitute(evaluated, rules)
    
    while true
        Symbolics.isequal(evaluated, try_evaluated) && break
        evaluated = try_evaluated
        try_evaluated = Symbolics.substitute(try_evaluated, rules)
    end
    
    return try_evaluated
end

function ref_to_symbolic!(expr::Expr, arrays::Dict)
    numdims = length(expr.args) - 1 # number of dimensions
    name = expr.args[1]
    index = expr.args[2:end]

    # if the array doesn't exist
    if !haskey(arrays, name)
        array = createsymbolicarray(name, index)
        arrays[name] = array
        return array[index...]
    end

    # if array exists
    array = arrays[name]
    # check if dimension match
    if ndims(array) == numdims
        old_size = size(array)
        if all([index[i] <= old_size[i] for i in eachindex(index)])
            return array[index...]
        
        else
            # expand the array
            new_size = collect(size(array))
            for i in eachindex(index)
                if index[i] > old_size[i]
                    new_size[i] = index[i]
                end
            end

            new_array = Array{Num}(undef, new_size...)
            for i in CartesianIndices(new_array)
                new_array[i] = tosymbolic(Symbol("$name"*"$(collect(Tuple(i)))"))
            end
            
            arrays[name] = new_array
            return new_array[index...] # again need to handle indexing later
        end
    end

    error("Dimension doesn't match!")
end

function parse_logical_assignments!(expr, rules, arrays)
    newrules = false
    for arg in expr.args
        if arg.head == :(=)
            lhs, rhs = arg.args

            # replace refs with symbolic variables
            # LHS should be simple, i.e. ref, variable or link function
            !isa(lhs, Symbol) || !MacroTools.isexpr(lhs, :ref) || error("LHS need to be simple.")
            if MacroTools.isexpr(lhs, :ref)
                lhs = Symbolics.tosymbol(ref_to_symbolic!(lhs, arrays))
            end
            
            ref_sym_variables = []
            rhs = MacroTools.prewalk(rhs) do sub_expr
                if MacroTools.isexpr(sub_expr, :ref)
                    sym_var = ref_to_symbolic!(sub_expr, arrays)
                    push!(ref_sym_variables, sym_var)
                    return Symbolics.tosymbol(sym_var)
                else
                    return sub_expr
                end
            end

            variables = find_all_variables(rhs)
            
            sym_rhs = create_sym_rhs(rhs, ref_sym_variables, variables)
            sym_lhs = tosymbolic(lhs)
            if haskey(rules, sym_lhs) 
                Symbolics.isequal(sym_rhs, rules[sym_lhs]) && continue
                error("Repeated definition for $(lhs)") 
            end
            rules[sym_lhs] = sym_rhs
            newrules = true
        end
    end
    return newrules
end

function parse_stochastic_assignments(expr, rules, arrays)
    stochastic_assign = Dict()
    for arg in expr.args
        if arg.head == :(~)
            lhs, rhs = arg.args

            # replace refs with symbolic variables
            # LHS should be simple, i.e. ref, variable or link function
            !isa(lhs, Symbol) || !MacroTools.isexpr(lhs, :ref) || error("LHS need to be simple.")
            if MacroTools.isexpr(lhs, :ref)
                lhs = Symbolics.tosymbol(ref_to_symbolic!(lhs, arrays))
            end
            
            # rhs will be a distribution object, so handle the distribution right now
            rhs.head == :call || error("RHS needs to be a distribution function")
            dist_func = eval(rhs.args[1])
            Base.@isdefined(dist_func) || error("$rhs not defined.")
            dist_args = rhs.args[2:end]

            ref_sym_variables = []
            rhs = MacroTools.prewalk(rhs) do sub_expr
                if MacroTools.isexpr(sub_expr, :ref)
                    sym_var = ref_to_symbolic!(sub_expr, arrays)
                    push!(ref_sym_variables, sym_var)
                    return Symbolics.tosymbol(sym_var)
                else
                    return sub_expr
                end
            end

            variables = find_all_variables(rhs)
            
            sym_rhs = create_sym_rhs(rhs, ref_sym_variables, variables)
            sym_lhs = tosymbolic(lhs)
            if haskey(stochastic_assign, sym_lhs) 
                Symbolics.isequal(sym_rhs, stochastic_assign[sym_lhs]) && continue
                error("Repeated definition for $(lhs)") 
            end
            stochastic_assign[sym_lhs] = sym_rhs
        end
    end
    return stochastic_assign
end

function create_sym_rhs(rhs, ref_sym_variables, variables)
    # bind symbolic variables to local variable with same names
    # so that when eval creates a symbolic expression 
    eval(local_binding_exprs(ref_sym_variables))
    eval(local_binding_exprs(variables))
    return eval(rhs)
end

function local_binding_exprs(sym_vars)
    ret_expr = []
    for sym_var in sym_vars
        assignment_expr = Expr(:(=), Symbolics.tosymbol(sym_var),  sym_var)
        push!(ret_expr, assignment_expr) 
    end
    return Expr(:block, ret_expr...)
end

# Find all the variables(Symbol) in expr
function find_all_variables(rhs)
    variables = []
    recursive_find_variables(rhs, variables)
    return map(tosymbolic, variables)
end

function recursive_find_variables(expr, leaves)
    # pre-order is important here
    MacroTools.prewalk(expr) do sub_expr
        if MacroTools.isexpr(sub_expr, :call)
            for arg in sub_expr.args[2:end]
                if isa(arg, Symbol) 
                    # filter out the variables turned from ref objects
                    Base.occursin("[", string(arg)) || push!(leaves, arg)
                end
                recursive_find_variables(arg, leaves)
            end
        end
    end
end

function to_symbol(lhs, rules, arrays)
    if isa(lhs, Symbol)
        return lhs
    elseif isa(lhs, Num)
        return Symbolics.tosymbol(lhs)
    elseif MacroTools.isexpr(lhs, :ref)
        return Symbolics.tosymbol(ref_to_symbolic!(lhs, rules, arrays))
    end
    error("Type of supported.")
end

# at this point, all the for loops should already be unrolled
function tograph(rules, arrays, stochastic_rules)
    # node_name => (default_value, function, node_type)
    to_graph = Dict()
    
    # The assumption behind this is that rules and stochastic_rules contain all the assignments in the definition, needs tests!!
    for key in keys(rules)
        # Figuring out default values
        default_value = resolve(key, rules, arrays)
        @show isa(default_value, Union{Integer, AbstractFloat})
        if !isa(default_value, Union{Integer, AbstractFloat})
            default_value = 0
        end
        default_value = Float64(default_value)
        # TODO: deal with multivar case later

        # Figuring out anonymous function
        ex = rules[key]
        args = Symbolics.get_variables(ex)
        f_expr = Symbolics.build_function(ex, args...)
        to_graph[Symbolics.tosymbol(key)] = (default_value, eval(f_expr), :Logical)

    end

    for key in keys(stochastic_rules)
        # Figuring out default values
        type = :Stochastic
        default_value = resolve(key, rules, arrays)
        if isa(default_value, Union{Integer, AbstractFloat}) 
            type = :Observation
        else 
            default_value = 0
        end
        default_value = Float64(default_value)
        ex = stochastic_rules[key]
        args = Symbolics.get_variables(ex)
        f_expr = Symbolics.build_function(ex, args...)

        to_graph[Symbolics.tosymbol(key)] = (default_value, eval(f_expr), type)
    end

    return to_graph
end

"""
Top level function
"""
function compile_graphppl(; model_def::Expr, data)    
    # Used to store all the arrays of symbolic variables
    arrays = Dict()
    # Store all the logical assignment for symbolics variables for partial evaluation
    rules = Dict()
    
    parsedata!(data, rules, arrays)
    
    # Alternate Unrolling and Parse logical assignments 
    while true 
        unrollforloops!(model_def, rules, arrays) || parse_logical_assignments!(expr, rules ,arrays) || break
    end
    stochastic_rules = parse_stochastic_assignments(expr, rules, arrays)

    # TODO: check if model_def still have unresolved loops or ifs remained
    model = tograph(rules, arrays, stochastic_rules)

    return Model(; zip(keys(model), values(model))...)
end

##