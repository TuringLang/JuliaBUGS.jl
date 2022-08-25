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
        # TODO: add supports for `missing` values
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

function create_symbolic_array(name::Symbol, size::Vector)
    symbolic_array = Array{Num}(undef, size...)
    for i in CartesianIndices(symbolic_array)
        symbolic_array[i] = tosymbolic(Symbol("$(name)" * "$(collect(Tuple(i)))"))
    end
    return symbolic_array
end

# this function should be handled as way as unroll
function resolve_if_conditions!(expr, compiler_state)
    for (i, arg) in enumerate(expr.args)
        if MacroTools.isexpr(arg, :if)
            condition = arg.args[1]
            block = arg.args[2]
            
            cond = resolve(condition, compiler_state)
            if cond isa Bool
                if cond 
                    splice!(expr.args, i, block.args)
                else 
                    pop!(expr.args, i)
                end
            elseif cond isa Real
                if cond > 0 
                    splice!(expr.args, i, block.args)
                else 
                    pop!(expr.args, i)
                end
            end
            return true # mutate once only
        end
    end         
    return false
end

#this function should be called before everything else
function lhs_link_function_to_rhs_inverse(expr, compiler_state)
    # link function only happens at lhs of logical assignment
    MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, f_(lhs_) = rhs_)
            if f in keys(INVERSE_LINK_FUNCTION)
                sub_expr.args[1] = lhs
                sub_expr.args[2] = Expr(:call, INVERSE_LINK_FUNCTION[f], rhs)
            else
                error("Link function $f not supported.")
            end
        end
        return sub_expr
    end
end

# TODO: what am I doing with array of symbolic variable anyway? do I even need it, it can be replaced with size + BitArray
# TODO: alternative array implement: keep a BitArray indicating if elements were referenced, and generate symbolic variable on the fly


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

tosymbolic(variable::Expr) =
    MacroTools.isexpr(variable, :ref) ? ref_to_symbolic!(variable, compiler_state) : error("General expression to symbol is not supported.")
tosymbolic(variable::Num) = variable
tosymbolic(variable::Union{Integer,AbstractFloat}) = Num(variable)
function tosymbolic(variable::Symbol) 
    variable_with_metadata = SymbolicUtils.setmetadata(
        SymbolicUtils.Sym{Real}(variable),
        Symbolics.VariableSource,
        (:variables, variable)
    )
    return Symbolics.wrap(variable_with_metadata)
end

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
    partial_trace = []
    evaluated = Symbolics.substitute(variable, compiler_state.rules)
    try_evaluated = Symbolics.substitute(evaluated, compiler_state.rules)
    push!(partial_trace, try_evaluated)

    while !Symbolics.isequal(evaluated, try_evaluated)
        evaluated = try_evaluated
        try_evaluated = Symbolics.substitute(try_evaluated, compiler_state.rules)
        try_evaluated in partial_trace && try_evaluated # avoiding infinite loop
    end

    return try_evaluated
end

Base.in(key::Num, vs::Vector{Any}) = any(broadcast(Symbolics.isequal, key, vs))

function ref_to_symbolic!(expr, compiler_state)
    numdims = length(expr.args) - 1 # number of dimensions
    name = expr.args[1]
    indices = expr.args[2:end]

    if !haskey(compiler_state.arrays, name)
        arraysize = deepcopy(indices)
        for (i, index) in enumerate(indices)
            if MacroTools.isexpr(index, :call)
                if index.args[1] == :(:)
                    low, high = index.args[2:end] # if size(args) > 3, error
                    indices[i] = eval(indices[i])
                else 
                    error("Wrong ref indexing expression.")
                end 
                arraysize[i] = high
            elseif index == :(:)
                arraysize[i] = 1
            end
        end
        array = create_symbolic_array(name, arraysize)
        compiler_state.arrays[name] = array
        return array[indices...]
    end

    # if array exists
    array = compiler_state.arrays[name]
    # TODO: if this is C, array is a pointer, but may later modify the object pointed by expanding array, improve this
    # check if number of dimensions match
    if ndims(array) == numdims
        array_size = collect(size(array))
        for (i, index) in enumerate(indices)
            if MacroTools.isexpr(index, :call)
                @assert index.args[1] == :(:) "Wrong ref indexing expression."
                
                low, high = index.args[2:end] # if size(args) > 3, error
                array_size[i] = max(array_size[i], high)

                indices[i] = eval(indices[i])
            elseif index == :(:)
                indices[i] = eval(indices[i])
            elseif isa(index, Integer)
                array_size[i] = max(indices[i], array_size[i])
            else
                error("Indexing wrong.")
            end
        end

        if all(array_size .== size(array))
            return array[indices...]
        else
            # expand the array
            expand_array!(name, array_size, compiler_state)
            return compiler_state.arrays[name][indices...] # again need to handle indexing later
        end
    end

    error("Dimension doesn't match!")
end

function expand_array!(name, size, compiler_state)
    new_array = Array{Num}(undef, size...)
    for i in CartesianIndices(new_array)
        new_array[i] = tosymbolic(Symbol("$name" * "$(collect(Tuple(i)))"))
    end

    compiler_state.arrays[name] = new_array
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
            if isempty(variables) && isempty(ref_variables)
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

issimpleexpression(expr) = Meta.isexpr(expr, (:(=), :~))

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

    all(issimpleexpression, expr.args) || error("Has unresolvable loop bounds or if conditions.")
    model = tograph(compiler_state)
    model_nt = (; model...)

    return Model(; model_nt...)
end
