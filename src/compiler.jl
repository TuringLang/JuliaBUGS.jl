using Distributions
using AbstractPPL.GraphPPL: Model
using Symbolics
using Random
using MacroTools
using LinearAlgebra
using BugsModels

struct CompilerState
    arrays::Dict{Symbol,Array{Num}}
    rules::Dict{Num,Num}
    stochastic_rules::Dict{Num,Num}
    constant_distribution_rules::Dict{Num,Any} # the value type right now is actually Function, as I store the anonymous function directly here, maybe change later

    # link_function_rules
end

CompilerState() = CompilerState(
    Dict{Symbol,Array{Num}}(),
    Dict{Num,Num}(),
    Dict{Num,Num}(),
    Dict{Num,Any}(),
)

parsedata!(data::NamedTuple, compiler_state) = parsedata!(Dict(pairs(data)), compiler_state)
function parsedata!(data::Dict, compiler_state)
    for (key, value) in data
        if isa(value, Number)
            compiler_state.rules[tosymbolic(key)] = value
        elseif isa(value, Array)
            sym_array = create_symbolic_array(key, collect(size(value)))
            for i in eachindex(value)
                compiler_state.rules[sym_array[i]] = value[i]
            end
            compiler_state.arrays[key] = sym_array
        else
            error("Value type not supported.")
        end
    end
end

function create_symbolic_array(name::Symbol, size)
    symbolic_array = Array{Num}(undef, size...)
    for i in CartesianIndices(symbolic_array)
        symbolic_array[i] = tosymbolic(Symbol("$(name)" * "$(collect(Tuple(i)))"))
    end
    return symbolic_array
end

function unrollforloops!(expr, compiler_state)
    unrolled_flag = false
    while hasforloop(expr, compiler_state)
        for (i, arg) in enumerate(expr.args)
            if arg.head == :for
                unrolled = unrollforloop(arg, compiler_state)
                splice!(expr.args, i, unrolled.args)
                unrolled_flag = true
                # unroll one loop at a time to avoid complication from mutation
                break
            end
        end
    end
    return unrolled_flag
end

function hasforloop(expr, compiler_state)
    for arg in expr.args
        if arg.head == :for
            lower_bound, higher_bound = arg.args[1].args[2].args
            lower_bound = resolve(lower_bound, compiler_state)
            higher_bound = resolve(higher_bound, compiler_state)
            if isa(lower_bound, Real) &&
               isa(higher_bound, Real) &&
               isinteger(lower_bound) &&
               isinteger(lower_bound)
                return true
            end
        end
    end
    return false
end

function unrollforloop(expr, compiler_state)
    loop_var = expr.args[1].args[1]
    lower_bound, higher_bound = expr.args[1].args[2].args
    body = expr.args[2]

    lower_bound = resolve(lower_bound, compiler_state)
    higher_bound = resolve(higher_bound, compiler_state)
    if isa(lower_bound, Real) &&
       isa(higher_bound, Real) &&
       isinteger(lower_bound) &&
       isinteger(lower_bound)
        unrolled_exprs = []
        for i = lower_bound:higher_bound
            # Replace all the loop variables in array indices with integers
            replaced_expr =
                MacroTools.postwalk(sub_expr -> sub_expr == loop_var ? i : sub_expr, body)
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
tosymbolic(variable::Symbol) = (identity)(
    (Symbolics.wrap)(
        (SymbolicUtils.setmetadata)(
            (SymbolicUtils.Sym){Real}(variable),
            Symbolics.VariableSource,
            (:variables, variable),
        ),
    ),
)
tosymbolic(variable::Expr) =
    MacroTools.isexpr(variable, :ref) && ref_to_symbolic!(variable, compiler_state)
tosymbolic(variable::Num) = variable
tosymbolic(variable::Union{Integer,AbstractFloat}) = Num(variable)

resolve(variable::Union{Integer,AbstractFloat}, compiler_state) = variable
function resolve(variable, compiler_state)
    resolved_variable = symbolic_eval(tosymbolic(variable), compiler_state)
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
function symbolic_eval(variable::Num, compiler_state)
    evaluated = Symbolics.substitute(variable, compiler_state.rules)
    try_evaluated = Symbolics.substitute(evaluated, compiler_state.rules)

    while true
        Symbolics.isequal(evaluated, try_evaluated) && break
        evaluated = try_evaluated
        try_evaluated = Symbolics.substitute(try_evaluated, compiler_state.rules)
    end

    return try_evaluated
end

function ref_to_symbolic!(expr::Expr, compiler_state)
    numdims = length(expr.args) - 1 # number of dimensions
    name = expr.args[1]
    index = expr.args[2:end]

    # if the array doesn't exist
    if !haskey(compiler_state.arrays, name)
        array = create_symbolic_array(name, index)
        compiler_state.arrays[name] = array
        return array[index...]
    end

    # if array exists
    array = compiler_state.arrays[name]
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
                new_array[i] = tosymbolic(Symbol("$name" * "$(collect(Tuple(i)))"))
            end

            compiler_state.arrays[name] = new_array
            return new_array[index...] # again need to handle indexing later
        end
    end

    error("Dimension doesn't match!")
end

function parse_logical_assignments!(expr, compiler_state)
    newrules_flag = false
    for arg in expr.args
        if arg.head == :(=)
            lhs, rhs = arg.args

            if MacroTools.isexpr(lhs, :ref)
                lhs = Symbolics.tosymbol(ref_to_symbolic!(lhs, compiler_state))
            end
            isa(lhs, Symbol) || error("LHS need to be simple.")

            ref_variables = []
            rhs = MacroTools.prewalk(rhs) do sub_expr
                if MacroTools.isexpr(sub_expr, :ref)
                    sym_var = ref_to_symbolic!(sub_expr, compiler_state)
                    push!(ref_variables, sym_var)
                    return Symbolics.tosymbol(sym_var)
                else
                    return sub_expr
                end
            end

            variables = find_all_variables(rhs)

            sym_rhs = create_sym_rhs(rhs, ref_variables, variables)
            sym_lhs = tosymbolic(lhs)
            if haskey(compiler_state.rules, sym_lhs)
                Symbolics.isequal(sym_rhs, compiler_state.rules[sym_lhs]) && continue
                error("Repeated definition for $(lhs)")
            end
            compiler_state.rules[sym_lhs] = sym_rhs
            newrules_flag = true
        end
    end
    return newrules_flag
end

"""
    This function should only be called when all the unrollings are done.
"""
function parse_stochastic_assignments!(expr, compiler_state)
    for arg in expr.args
        if arg.head == :(~)
            lhs, rhs = arg.args

            if MacroTools.isexpr(lhs, :ref)
                lhs = Symbolics.tosymbol(ref_to_symbolic!(lhs, compiler_state))
            end
            isa(lhs, Symbol) || error("LHS need to be simple.")

            # rhs will be a distribution object, so handle the distribution right now
            rhs.head == :call || error("RHS needs to be a distribution function")
            dist_func = rhs.args[1]
            dist_func in DISTRIBUTIONS || error("$rhs not defined.")

            ref_variables = []
            rhs = MacroTools.prewalk(rhs) do sub_expr
                if MacroTools.isexpr(sub_expr, :ref)
                    sym_var = ref_to_symbolic!(sub_expr, compiler_state)
                    push!(ref_variables, sym_var)
                    return Symbolics.tosymbol(sym_var)
                else
                    return sub_expr
                end
            end
            variables = find_all_variables(rhs)

            sym_rhs = create_sym_rhs(rhs, ref_variables, variables)
            sym_lhs = tosymbolic(lhs)
            if haskey(compiler_state.stochastic_rules, sym_lhs)
                Symbolics.isequal(sym_rhs, compiler_state.stochastic_rules[sym_lhs]) &&
                    continue
                error("Repeated definition for $(lhs)")
            end
            if size(variables) == (0,) && size(ref_variables) == (0,)
                # the distribution does not have variable arguments
                compiler_state.constant_distribution_rules[sym_lhs] = () -> sym_rhs
            else
                compiler_state.stochastic_rules[sym_lhs] = sym_rhs
            end
        end
    end
end

function create_sym_rhs(rhs, ref_variables, variables)
    # bind symbolic variables to local variable with same names
    binding_exprs = []
    for variable in vcat(ref_variables, variables)
        binding_expr = Expr(:(=), Symbolics.tosymbol(variable), variable)
        push!(binding_exprs, binding_expr)
    end

    # let-bind will bind a local variable to a symbolic variable with the 
    # same name, so that evaluating the rhs expression generating a symbolic term
    let_expr = Expr(:let, Expr(:block, binding_exprs...), rhs)

    # `eval` will then construct symbolic expression with the local bindings
    return eval(let_expr)
end

""" 
Find all the variables (which are Symbols in the expr)
"""
function find_all_variables(rhs)
    variables = []
    recursive_find_variables(rhs, variables)
    return map(tosymbolic, variables)
end

function recursive_find_variables(expr, variables)
    # pre-order traversal is important here
    MacroTools.prewalk(expr) do sub_expr
        if MacroTools.isexpr(sub_expr, :call)
            # doesn't touch function identifiers
            for arg in sub_expr.args[2:end]
                if isa(arg, Symbol)
                    # filter out the variables turned from ref objects
                    Base.occursin("[", string(arg)) || push!(variables, arg)
                end
                recursive_find_variables(arg, variables)
            end
        end
    end
end

to_symbol(lhs::Symbol, compiler_state) = lhs
to_symbol(lhs::Num, compiler_state) = Symbolics.tosymbol(lhs)
function to_symbol(lhs::Expr, compiler_state)
    if MacroTools.isexpr(lhs, :ref)
        return Symbolics.tosymbol(ref_to_symbolic!(lhs, compiler_state))
    end
    error("Only ref expressions are supported.")
end

function tograph(compiler_state)
    # node_name => (default_value, function, node_type)
    to_graph = Dict()

    for key in keys(compiler_state.rules)
        default_value = resolve(key, compiler_state)
        if !isa(default_value, Union{Integer,AbstractFloat})
            default_value = 0
        end
        default_value = Float64(default_value)

        ex = compiler_state.rules[key]
        args = Symbolics.get_variables(ex)
        f_expr = Symbolics.build_function(ex, args...)
        to_graph[Symbolics.tosymbol(key)] = (default_value, eval(f_expr), :Logical)
    end

    for key in keys(compiler_state.stochastic_rules)
        type = :Stochastic
        default_value = resolve(key, compiler_state)
        if isa(default_value, Union{Integer,AbstractFloat})
            type = :Observations
        else
            default_value = 0
        end
        default_value = Float64(default_value)
        ex = compiler_state.stochastic_rules[key]
        args = Symbolics.get_variables(ex)
        f_expr = Symbolics.build_function(ex, args...)

        to_graph[Symbolics.tosymbol(key)] = (default_value, eval(f_expr), type)
    end

    for key in keys(compiler_state.constant_distribution_rules)
        type = :Stochastic
        default_value = resolve(key, compiler_state)
        if isa(default_value, Union{Integer,AbstractFloat})
            type = :Observations
        else
            default_value = 0
        end
        default_value = Float64(default_value)

        to_graph[Symbolics.tosymbol(key)] =
            (default_value, compiler_state.constant_distribution_rules[key], type)
    end

    return to_graph
end

function onlysimpleexpr(expr::Expr)
    for arg in expr.args
        if !MacroTools.isexpr(arg, :(=)) && !MacroTools.isexpr(arg, :~)
            return false
        end
    end
    return true
end

"""
Top level function
"""
function compile_graphppl(; model_def::Expr, data)
    expr = deepcopy(model_def)
    compiler_state = CompilerState()
    parsedata!(data, compiler_state)

    while true
        unrollforloops!(expr, compiler_state) ||
            parse_logical_assignments!(expr, compiler_state) ||
            break
    end
    parse_stochastic_assignments!(expr, compiler_state)

    onlysimpleexpr(expr) || error("Has unresolvable loop bounds or if conditions.")
    model = tograph(compiler_state)
    model_nt = (; model...)

    return Model(; model_nt...)
end
