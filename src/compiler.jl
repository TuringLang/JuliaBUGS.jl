using Distributions
using AbstractPPL.GraphPPL: Model, set_node_value!
using Symbolics
using Random
using MacroTools
using LinearAlgebra

"""
    CompilerState

`arrays` is a dictionary maps array names form model definition to arrays of symbolics variables. Indexing 
in model definition is implemented as indexing to the arrays stored in `arrays`. `logicalrules` and `stochasticrules` are 
dictionary that maps symbolic variables to there equivalent julia symbolic expressions. Partial evaluation of variables 
are implemented as symbolic substitution. 

CompilerState will likely eb mutated multiple times. And the final step of the compiling into GraphPPL only rely on data 
in CompilerState.
"""
struct CompilerState
    arrays::Dict{Symbol,Array{Num}}
    logicalrules::Dict{Num,Num}
    stochasticrules::Dict{Num,Any}
end

CompilerState() = CompilerState(
    Dict{Symbol,Array{Num}}(),
    Dict{Num,Num}(),
    Dict{Num,Any}(),
)

"""
    resolveif!(expr, compiler_state)

Evaluate the condition of the `if` statement. And in the situation where the condition is true,
hoist out the consequence; otherwise, discard the if statement.
"""
function resolveif!(expr::Expr, compiler_state::CompilerState)
    squashed = false
    while any(arg -> Meta.isexpr(arg, :if), expr.args)
        for (i, arg) in enumerate(expr.args)
            if MacroTools.isexpr(arg, :if)
                condition = arg.args[1]
                block = arg.args[2]

                cond = resolve(condition, compiler_state)
                if cond isa Bool
                    if cond
                        splice!(expr.args, i, block.args)
                    else
                        deleteat!(expr.args, i)
                    end
                    squashed = true # mutate once only, call this function until no mutation to settle multiple ifs
                    break
                end
            end
        end
    end
    return squashed
end

"""
    inverselinkfunction(expr)

For all the logical assignments with supported link functions on the LHS. Rewrite the equation so that the 
LHS is the argument of the link function, and the new RHS is a call to the inverse of the link function whose 
argument is the original RHS.  
"""
function inverselinkfunction(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
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

"""
    unrollforloops!(expr, compiler_state)

Unroll all the loops whose loop bounds can be partially evaluated to a constant. 
"""
function unrollforloops!(expr::Expr, compiler_state::CompilerState)
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

function hasforloop(expr::Expr, compiler_state::CompilerState)
    for arg in expr.args
        if arg.head == :for
            lower_bound, higher_bound = arg.args[1].args[2].args
            lower_bound = resolve(lower_bound, compiler_state)
            higher_bound = resolve(higher_bound, compiler_state)
            if lower_bound isa Real &&
               higher_bound isa Real &&
               isinteger(lower_bound) &&
               isinteger(lower_bound)
                return true
            end
        end
    end
    return false
end

function unrollforloop(expr::Expr, compiler_state::CompilerState)
    loop_var = expr.args[1].args[1]
    lower_bound, higher_bound = expr.args[1].args[2].args
    body = expr.args[2]

    lower_bound = resolve(lower_bound, compiler_state)
    higher_bound = resolve(higher_bound, compiler_state)
    if lower_bound isa Real &&
       higher_bound isa Real &&
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
    elseif lower_bound isa AbstractFloat || higher_bound isa AbstractFloat
        error("Loop bounds need to be integers.")
    else
        # if loop bounds contain variables that can't be partial evaluated at this moment
        return expr
    end
end

"""
    tosymbolic(variable)

Returns symbolic variable for multiple types of `variable`s. If the argument is an Expr, then
the function will return a symbolic variable in the case where argument is a `ref` Expr, otherwise
a symbolic term. 
"""
tosymbolic(variable::Num) = variable
tosymbolic(variable::Union{Integer,AbstractFloat}) = Num(variable)
tosymbolic(variable::String) = tosymbolic(Symbol(variable))
function tosymbolic(variable::Symbol)
    variable_with_metadata = SymbolicUtils.setmetadata(
        SymbolicUtils.Sym{Real}(variable),
        Symbolics.VariableSource,
        (:variables, variable),
    )
    return Symbolics.wrap(variable_with_metadata)
end
function tosymbolic(expr::Expr)
    if MacroTools.isexpr(expr, :ref)  
        return tosymbolic(Symbol(expr))
    else
        ref_variables = []
        ex = MacroTools.prewalk(expr) do sub_expr
            if MacroTools.isexpr(sub_expr, :ref)
                sym_var = tosymbolic(sub_expr)
                push!(ref_variables, sym_var)
                return Symbolics.tosymbol(sym_var)
            else
                return sub_expr
            end
        end
        variables = find_all_variables(ex)
        return create_sym_rhs(ex, vcat(ref_variables, variables))
    end
end
tosymbolic(variable) = variable
    
"""
    resolve(variable, compiler_state)

Partially evaluate the variable in the context defined by compiler_state.
"""
resolve(variable::Union{Integer,AbstractFloat}, compiler_state::CompilerState) = variable
function resolve(variable, compiler_state::CompilerState)
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
    So this function provide a temporary solution by trying to recursively resolve the variable.
"""
function symbolic_eval(variable::Num, compiler_state::CompilerState)
    partial_trace = []
    evaluated = Symbolics.substitute(variable, compiler_state.logicalrules)
    try_evaluated = Symbolics.substitute(evaluated, compiler_state.logicalrules)
    push!(partial_trace, try_evaluated)

    while !Symbolics.isequal(evaluated, try_evaluated)
        evaluated = try_evaluated
        try_evaluated = Symbolics.substitute(try_evaluated, compiler_state.logicalrules)
        try_evaluated in partial_trace && break # avoiding infinite loop
    end

    return try_evaluated
end
symbolic_eval(variable::UnitRange{Int64}, compiler_state::CompilerState) = variable # Special case for array range

Base.in(key::Num, vs::Vector{Any}) = any(broadcast(Symbolics.isequal, key, vs))

"""
    ref_to_symbolic!(expr, compiler_state)

Specialized for :ref expressions. If the referred array was seen, then return the corresponding symbolic
variable; otherwise, allocate array in `CompilerState.arrays`, then return the symbolic variable or array.
"""
function ref_to_symbolic!(expr::Expr, compiler_state::CompilerState)
    numdims = length(expr.args) - 1
    name = expr.args[1]
    indices = expr.args[2:end]
    for (i, index) in enumerate(indices)
        if index isa Expr
            resolved_index = resolve(tosymbolic(index), compiler_state)
            if !isa(resolved_index, Union{Number, UnitRange})
                return tosymbolic("SKIP")
            end 
            # || error("$index can't be evaluated to a concrete value.") 
            if !isa(resolved_index, Number) && !isinteger(resolved_index)
                error("Index of $expr needs to be integers.")
            end
            indices[i] = Integer(resolved_index)
        end
    end

    if !haskey(compiler_state.arrays, name)
        arraysize = deepcopy(indices)
        for (i, index) in enumerate(indices)
            if index isa UnitRange
                arraysize[i] = index[end]
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
    if ndims(array) == numdims
        array_size = collect(size(array))
        for (i, index) in enumerate(indices)
            if index isa UnitRange
                array_size[i] = max(array_size[i], index[end]) # in case 'high' is Expr
            elseif index == :(:)
                indices[i] = eval(indices[i])
            elseif index isa Integer
                array_size[i] = max(indices[i], array_size[i])
            else
                error("Indexing syntax is wrong.")
            end
        end

        if all(array_size .== size(array))
            return array[indices...]
        else
            expand_array!(name, array_size, compiler_state)
            return compiler_state.arrays[name][indices...]
        end
    end

    error("Dimension doesn't match!")
end

function expand_array!(name::Symbol, size::Vector{<:Integer}, compiler_state::CompilerState)
    new_array = Array{Num}(undef, size...)
    for i in CartesianIndices(new_array)
        new_array[i] = tosymbolic(Symbol("$name" * "$(collect(Tuple(i)))"))
    end

    compiler_state.arrays[name] = new_array
end

function create_symbolic_array(name::Symbol, size::Vector)
    symbolic_array = Array{Num}(undef, size...)
    for i in CartesianIndices(symbolic_array)
        symbolic_array[i] = tosymbolic(Symbol("$(name)" * "$(collect(Tuple(i)))"))
    end
    return symbolic_array
end

addlogicalrules!(data::NamedTuple, compiler_state::CompilerState) =
    addlogicalrules!(Dict(pairs(data)), compiler_state)
function addlogicalrules!(data::Dict, compiler_state::CompilerState)
    for (key, value) in data
        if value isa Number
            compiler_state.logicalrules[tosymbolic(key)] = value
        elseif value isa Array
            sym_array = create_symbolic_array(key, collect(size(value)))
            for i in eachindex(value)
                if !isequal(value[i], missing)
                    compiler_state.logicalrules[sym_array[i]] = value[i]
                end
            end
            compiler_state.arrays[key] = sym_array
        else
            error("Value type not supported.")
        end
    end
end
function addlogicalrules!(expr::Expr, compiler_state::CompilerState)
    newrules_flag = false
    for arg in expr.args
        if arg.head == :(=)
            lhs, rhs = arg.args

            if MacroTools.isexpr(lhs, :ref)
                sym_var = ref_to_symbolic!(lhs, compiler_state)
                if Symbolics.isequal(sym_var, tosymbolic("SKIP"))
                    continue
                end
                lhs = Symbolics.tosymbol(sym_var)
            end
            lhs isa Symbol || error("LHS need to be simple.")

            rhs, ref_variables = find_ref_variables(rhs, compiler_state)
            if !isempty(ref_variables) && Symbolics.isequal(ref_variables[1], tosymbolic("SKIP"))
                continue
            end
            variables = find_all_variables(rhs)

            sym_rhs = create_sym_rhs(rhs, vcat(ref_variables, variables))
            sym_lhs = tosymbolic(lhs)
            if haskey(compiler_state.logicalrules, sym_lhs)
                Symbolics.isequal(sym_rhs, compiler_state.logicalrules[sym_lhs]) && continue
                error("Repeated definition for $(lhs)")
            end
            compiler_state.logicalrules[sym_lhs] = sym_rhs
            newrules_flag = true
        end
    end
    return newrules_flag
end

"""
    addstochasticrules!(expr, compiler_state::CompilerState)

Process all the stochastic assignments and add them to `CompilerState.stochasticrules`.
"""
function addstochasticrules!(expr::Expr, compiler_state::CompilerState)
    for arg in expr.args
        if arg.head == :(~)
            lhs, rhs = arg.args

            if Meta.isexpr(rhs, [:truncated, :censored])
                l, u = rhs.args[2:3]
                parameters = Vector{Any}()
                if l != :nothing
                    push!(parameters, (:kw, :lower, l))
                end
                if u != :nothing
                    push!(parameters, (:kw, :upper, u))
                end
                    
                rhs = Expr(:call, rhs.head, (:parameters, parameters...), rhs.args[1])
            end

            if MacroTools.isexpr(lhs, :ref)
                sym_var = ref_to_symbolic!(lhs, compiler_state)
                if Symbolics.isequal(sym_var, tosymbolic("SKIP"))
                    error("Exists unresolvable indexing at $arg.")
                end
                lhs = Symbolics.tosymbol(sym_var)
            end
            lhs isa Symbol || error("LHS need to be simple.")

            # rhs will be a distribution object, so handle the distribution right now
            if rhs.head == :call
                dist_func = rhs.args[1]
                dist_func in DISTRIBUTIONS || error("$dist_func not defined.") # DISTRIBUTIONS defined in "primitive.jl"
            elseif rhs.head in (:truncated, :censored, )
                dist_func = rhs.args[1].args[1]
                dist_func in DISTRIBUTIONS || error("$dist_func not defined.") # DISTRIBUTIONS defined in "primitive.jl"
            else
                error("RHS needs to be a distribution function")
            end

            rhs, ref_variables = find_ref_variables(rhs, compiler_state)
            if !isempty(ref_variables) && Symbolics.isequal(ref_variables[1], tosymbolic("SKIP"))
                error("Exists unresolvable indexing at $arg.")
            end
            variables = find_all_variables(rhs)

            sym_lhs = tosymbolic(lhs)

            arguments = map(Symbolics.tosymbol, vcat(variables, ref_variables))
            func_expr = Expr(:(->), Expr(:tuple, arguments...), Expr(:block, rhs))
            func = eval(func_expr) # anonymous function, so doesn't contaminate the environment, but still maybe a better solution out there 

            if haskey(compiler_state.stochasticrules, sym_lhs)
                error("Repeated definition for $(lhs)")
            end
            
            compiler_state.stochasticrules[sym_lhs] = func
        end
    end
end

find_ref_variables(rhs::Number, compiler_state::CompilerState) = rhs, []
function find_ref_variables(rhs::Expr, compiler_state::CompilerState)
    ref_variables = []
    replaced_rhs = MacroTools.prewalk(rhs) do sub_expr
        if MacroTools.isexpr(sub_expr, :ref)
            sym_var = ref_to_symbolic!(sub_expr, compiler_state)
            if Symbolics.isequal(sym_var, tosymbolic("SKIP")) # Some index can't be resolved in this generation
                push!(ref_variables, tosymbolic("SKIP")) # Put the SKIP signal in the returned variable vector
                return sub_expr
            end
            push!(ref_variables, sym_var)
            return Symbolics.tosymbol(sym_var)
        else
            return sub_expr
        end
    end
    return replaced_rhs, ref_variables
end

create_sym_rhs(rhs::Number, variables::Vector) = rhs
create_sym_rhs(rhs::Symbol, variables::Vector) = tosymbolic(rhs)
function create_sym_rhs(rhs::Expr, variables::Vector)
    # bind symbolic variables to local variable with same names
    binding_exprs = []
    for variable in variables
        if !isempty(size(variable)) # Vector
            for i in eachindex(variable)
            binding_expr = Expr(:(=), Symbolics.tosymbol(variable[i]), variable[i])
            push!(binding_exprs, binding_expr)
            end
        else
            binding_expr = Expr(:(=), Symbolics.tosymbol(variable), variable)
            push!(binding_exprs, binding_expr)
        end
    end

    # let-bind will bind a local variable to a symbolic variable with the 
    # same name, so that evaluating the rhs expression generating a symbolic term
    let_expr = Expr(:let, Expr(:block, binding_exprs...), rhs)

    return eval(let_expr) # this can be bad, as the type of the return value is not clear
end

find_all_variables(rhs::Number) = []
find_all_variables(rhs::Symbol) = Base.occursin("[", string(rhs)) ? [] : rhs
function find_all_variables(rhs::Expr)
    variables = []
    recursive_find_variables(rhs, variables)
    return map(tosymbolic, variables)
end

function recursive_find_variables(expr::Expr, variables::Vector{Any})
    # pre-order traversal is important here
    MacroTools.prewalk(expr) do sub_expr
        if MacroTools.isexpr(sub_expr, :call)
            # doesn't touch function identifiers
            for arg in sub_expr.args[2:end]
                if arg isa Symbol && !Base.occursin("[", string(arg))
                    push!(variables, arg)
                    continue
                end
                arg isa Expr && recursive_find_variables(arg, variables)
            end
        end
    end
end

# to_symbol(lhs::Symbol, compiler_state::CompilerState) = lhs
# to_symbol(lhs::Num, compiler_state::CompilerState) = Symbolics.tosymbol(lhs)
# function to_symbol(lhs::Expr, compiler_state::CompilerState)
#     if MacroTools.isexpr(lhs, :ref)
#         return Symbolics.tosymbol(ref_to_symbolic!(lhs, compiler_state))
#     end
#     error("Only ref expressions are supported.")
# end

function tograph(compiler_state::CompilerState)
    # node_name => (default_value, function, node_type)
    to_graph = Dict()

    for key in keys(compiler_state.logicalrules)
        default_value = resolve(key, compiler_state)
        isconstant = false
        if !isa(default_value, Union{Integer,AbstractFloat})
            # default_value can be set directly on compiler GraphPPL.Model 
            default_value = 0
        else
            isconstant = true
        end
        default_value = Float64(default_value)

        ex = compiler_state.logicalrules[key]
        args = Symbolics.get_variables(ex)
        f_expr = Symbolics.build_function(ex, args...)
        # hack to make GraphPPL happy: change the function definition to return a Float64 type
        if isconstant
            f_expr.args[2].args[end] = Expr(:call, Float64, f_expr.args[2].args[end])
        end
        to_graph[Symbolics.tosymbol(key)] = (default_value, eval(f_expr), :Logical)
    end

    for key in keys(compiler_state.stochasticrules)
        type = :Stochastic
        default_value = resolve(key, compiler_state)
        if isa(default_value, Union{Integer,AbstractFloat})
            type = :Observations
        else
            default_value = 0
        end
        default_value = Float64(default_value)

        to_graph[Symbolics.tosymbol(key)] =
            (default_value, compiler_state.stochasticrules[key], type)
    end

    return to_graph
end

issimpleexpression(expr) = Meta.isexpr(expr, (:(=), :~))

"""
    compile_graphppl(; model_def::Expr, data)

The exported top level function. `compile_graphppl` takes model definition and data and returns a GraphPPL.Model.
"""
function compile_graphppl(; model_def::Expr, data::NamedTuple, initials=nothing) 
    expr = inverselinkfunction(model_def)
    compiler_state = CompilerState()
    addlogicalrules!(data, compiler_state)

    while true
        unrollforloops!(expr, compiler_state) ||
            resolveif!(expr, compiler_state) ||
            addlogicalrules!(expr, compiler_state) ||
            break
    end
    addstochasticrules!(expr, compiler_state)

    all(issimpleexpression, expr.args) ||
        error("Has unresolvable loop bounds or if conditions.")
    model = tograph(compiler_state)
    model_nt = (; model...)

    graphmodel = Model(; model_nt...)
    
    if !isnothing(initials)
        for variable in keys(initials)
            if !isempty(size(initials[variable]))
                for i in CartesianIndices(initials[variable])
                    vn = AbstractPPL.VarName(Symbol("$variable" * "$(collect(Tuple(i)))"))
                    set_node_value!(graphmodel, vn, initials[variable][i])
                end
            else
                set_node_value!(graphmodel, AbstractPPL.VarName(variable), initials[variable])
            end
        end
    end

    return graphmodel
end
