using Distributions
using AbstractPPL.GraphPPL: Model
using Symbolics
using SymbolicUtils
using Random
using MacroTools
using LinearAlgebra
using Accessors

"""
    CompilerState

Store data during the compilation. 
"""
struct CompilerState
    arrays::Dict{Symbol,Symbolics.Arr{Num}}
    logicalrules::Dict{Any,Any}
    stochasticrules::Dict{Num,Expr}
end

CompilerState() = CompilerState(
    Dict{Symbol,Symbolics.Arr{Num}}(),
    Dict{Any,Any}(),
    Dict{Num,Expr}()
)

"""
    resolveif!(expr, compiler_state)

Try ['resolve'](@ref) the condition of the `if` statement. If condition is true, hoist out the consequence; 
otherwise, discard the whole `if` statement.
"""
function resolveif!(expr::Expr, compiler_state::CompilerState)
    squashed = false
    while any(arg -> Meta.isexpr(arg, :if), expr.args)
        for (i, arg) in enumerate(expr.args)
            if MacroTools.isexpr(arg, :if)
                condition = arg.args[1]
                block = arg.args[2]
                @assert size(arg.args) === (2,)

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
    convert_cumulative(expr)

Convert `cumulative(s1, s2)` to `cdf(distribution_of_s1, s2)`.
"""
function convert_cumulative(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = cumulative(s1_, s2_))
            dist = find_dist(expr, s1)
            sub_expr.args[2].args[1] = :cdf 
            sub_expr.args[2].args[2] = dist
            return sub_expr
        else
            return sub_expr
        end
    end
end

function find_dist(expr::Expr, target::Union{Expr, Symbol})
    dist = nothing
    MacroTools.postwalk(expr) do sub_expr
        if isexpr(sub_expr, :(~))
            if sub_expr.args[1] == target
                isnothing(dist) || error("Exist two assignments to the same variable.")
                dist = sub_expr.args[2]
            end
        end
        return sub_expr
    end
    isnothing(dist) && error("Didn't find a stochastic assignment for $target.")
    return dist
end

"""
    inverselinkfunction(expr)

Call the inverse of the link function on the RHS so that the LHS is simple. 
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
    translate_censoring_expressions(expr)

Turn `censored` expression to function calls.
"""
function translate_censoring_expressions(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :censored)
            l, u = sub_expr.args[2:3]

            if l != :nothing && u != :nothing
                return Expr(:call, :censored, sub_expr.args...)
            elseif l != :nothing
                return Expr(:call, :censored_with_lower, sub_expr.args[1], l)
            else # u != :nothing
                return Expr(:call, :censored_with_upper, sub_expr.args[1], u)
            end
        else
            return sub_expr
        end
    end
end

"""
    translate_truncating_expressions(expr)

Turn `truncated` expression to function calls.
"""
function translate_truncating_expressions(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :truncated)
            l, u = sub_expr.args[2:3]

            if l != :nothing && u != :nothing
                return Expr(:call, :truncated, sub_expr.args...)
            elseif l != :nothing
                return Expr(:call, :truncated_with_lower, sub_expr.args[1], l)
            else # u != :nothing
                return Expr(:call, :truncated_with_upper, sub_expr.args[1], u)
            end
        else
            return sub_expr
        end
    end
end

"""
    unrollforloops!(expr, compiler_state)

Unroll all the loops whose loop bounds can be partially evaluated to a constant. 
"""
function unrollforloops!(expr::Expr, compiler_state::CompilerState)
    hasunrolled = false
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
    return hasunrolled
end

function hasforloop(expr::Expr, compiler_state::CompilerState)
    for arg in expr.args
        if arg.head == :for
            lower_bound, upper_bound = arg.args[1].args[2].args
            lower_bound = resolve(lower_bound, compiler_state)
            upper_bound = resolve(upper_bound, compiler_state)
            if lower_bound isa Real &&
                upper_bound isa Real &&
               isinteger(lower_bound) &&
               isinteger(upper_bound)
                return true
            end
        end
    end
    return false
end

function unrollforloop(expr::Expr, compiler_state::CompilerState)
    loop_var = expr.args[1].args[1]
    lower_bound, upper_bound = expr.args[1].args[2].args
    body = expr.args[2]

    lower_bound = resolve(lower_bound, compiler_state)
    upper_bound = resolve(upper_bound, compiler_state)
    if lower_bound isa Real &&
        upper_bound isa Real &&
       isinteger(lower_bound) &&
       isinteger(upper_bound)
        unrolled_exprs = []
        for i = lower_bound:upper_bound
            # Replace all the loop variables in array indices with integers
            replaced_expr =
                MacroTools.postwalk(sub_expr -> sub_expr == loop_var ? i : sub_expr, body)
            push!(unrolled_exprs, replaced_expr.args...)
        end
        return Expr(:block, unrolled_exprs...)
    elseif lower_bound isa AbstractFloat || upper_bound isa AbstractFloat
        error("Loop bounds need to be integers.")
    else
        # if loop bounds contain variables that can't be partial evaluated at this moment
        return expr
    end
end

"""
    tosymbolic(variable)

Returns symbolic variable for multiple types of `variable`s. 
"""
tosymbolic(variable::Num) = variable
tosymbolic(variable::Union{Integer,AbstractFloat}) = Num(variable)
tosymbolic(variable::String) = tosymbolic(Symbol(variable))
function tosymbolic(variable::Symbol)
    if Meta.isexpr(Meta.parse(string(variable)), :ref)
        return ref_to_symbolic(string(variable))
    end

    variable_with_metadata = SymbolicUtils.setmetadata(
        SymbolicUtils.Sym{Real}(variable),
        Symbolics.VariableSource,
        (:variables, variable),
    )
    return Symbolics.wrap(variable_with_metadata)
end
function tosymbolic(expr::Expr)
    if MacroTools.isexpr(expr, :ref)  
        return ref_to_symbolic(expr)
    else
        variables = find_all_variables(expr)
        expr = replace_variables(expr, variables)
        return eval(expr)
    end
end
function tosymbolic(array_name::Symbol, array_size::Vector)
    array_ranges = Tuple([(1:i) for i in array_size])
    variable_with_metadata = SymbolicUtils.setmetadata(
        SymbolicUtils.setmetadata(
            SymbolicUtils.Sym{Array{Real, (length)(array_ranges)}}(array_name), Symbolics.ArrayShapeCtx, array_ranges), 
            Symbolics.VariableSource, 
            (:variables, array_name))
    return Symbolics.wrap(variable_with_metadata)
end
tosymbolic(variable) = variable

tosymbol(x) = beautify_ref_symbol(Symbolics.tosymbol(x))

function beautify_ref_symbol(s::Symbol)
    m = match(r"getindex\((.*),\s(.*)\)", string(s))
    if !isnothing(m)
        indices = String[]
        name = :nothing
        while !isnothing(m)
            push!(indices, m.captures[end])
            name = m.captures[1]
            m = match(r"(.*),\s(.*)",  string(m.captures[1]))
        end
        indices = reverse(map(Meta.parse, indices))
        return Symbol("$name$indices")
    else
        return s
    end
end

"""
    ref_to_symbolic!(expr, compiler_state)

Return a symbolic variable for the referred array element. May mutate the compiler_state.
"""
ref_to_symbolic(s::String) = ref_to_symbolic(Meta.parse(s))
function ref_to_symbolic(expr::Expr)
    name = expr.args[1]
    indices = map(eval, expr.args[2:end]) # deal with case like a[:(2-1):2]
    if any(x->!isa(x, Integer), indices)
        error("Only support integer indices.")
    end
    ret = tosymbolic(name, indices)
    return ret[indices...]
end
function ref_to_symbolic!(expr::Expr, compiler_state::CompilerState)
    numdims = length(expr.args) - 1
    name = expr.args[1]
    indices = expr.args[2:end]
    for (i, index) in enumerate(indices)
        if index isa Expr
            if Meta.isexpr(index, :call) && index.args[1] == :(:)
                lb = resolve(index.args[2], compiler_state) 
                ub = resolve(index.args[3], compiler_state)
                if lb isa Real && ub isa Real
                    indices[i].args[2] = lb
                    indices[i].args[3] = ub
                else
                    return __SKIP__
                end
            end

            resolved_index = resolve(tosymbolic(index), compiler_state)
            if !isa(resolved_index, Union{Number, UnitRange})
                return __SKIP__
            end 

            if isa(resolved_index, Number) 
                isinteger(resolved_index) || error("Index of $expr needs to be integers.")
                indices[i] = Integer(resolved_index)
            else
                indices[i] = resolved_index
            end
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
        array = tosymbolic(name, arraysize)
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
                indices[i] = Colon()
            elseif index isa Integer
                array_size[i] = max(indices[i], array_size[i])
            else
                error("Indexing syntax is wrong.")
            end
        end

        if all(array_size .== size(array))
            return array[indices...]
        else
            compiler_state.arrays[name] = tosymbolic(name, array_size)
            return compiler_state.arrays[name][indices...]
        end
    end

    error("Dimension doesn't match!")
end

const __SKIP__ = tosymbolic("SKIP")

"""
    resolve(variable, compiler_state)

Partially evaluate the variable in the context defined by compiler_state.
"""
resolve(variable::Union{Integer,AbstractFloat}, compiler_state::CompilerState) = variable
function resolve(variable, compiler_state::CompilerState)
    resolved_variable = symbolic_eval(tosymbolic(variable), compiler_state)
    return Symbolics.unwrap(resolved_variable)
end
function symbolic_eval(variable, compiler_state::CompilerState)
    if variable isa Symbolics.Arr{Num}
        variable = Symbolics.scalarize(variable)
    end
    partial_trace = []
    evaluated = Symbolics.substitute(variable, compiler_state.logicalrules)

    let e = Symbolics.toexpr(evaluated) 
        if Meta.isexpr(e, :call) && in(Symbol(e.args[1]), [:exp]) # if symbolicly traced, can be more general, only handle :exp now
            func = e.args[1]
            nargs = size(e.args)[1] - 1
            args = arguments(Symbolics.unwrap(evaluated))
            resolved_args = []
            for i in 1:nargs
                arg = Symbolics.wrap(args[i])
                resolved_arg = symbolic_eval(arg, compiler_state)
                push!(resolved_args, resolved_arg)
            end
            return func(resolved_args...)
        end
    end

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

Base.in(key::Num, vs::Vector) = any(broadcast(Symbolics.isequal, key, vs))

"""
    addlogicalrules!(data, compiler_state)

Process all the logical assignments and add them to `CompilerState.stochasticrules`.
"""
addlogicalrules!(data::NamedTuple, compiler_state::CompilerState) =
    addlogicalrules!(Dict(pairs(data)), compiler_state)
function addlogicalrules!(data::Dict, compiler_state::CompilerState)
    for (key, value) in data
        if value isa Number
            compiler_state.logicalrules[tosymbolic(key)] = value
        elseif value isa Array
            sym_array = tosymbolic(key, collect(size(value)))
            compiler_state.logicalrules[sym_array] = value
            compiler_state.arrays[key] = sym_array
        else
            error("Value type not supported.")
        end
    end
end
function addlogicalrules!(expr::Expr, compiler_state::CompilerState)
    addednewrules = false
    for arg in expr.args
        if arg.head == :(=)
            lhs, rhs = arg.args

            if MacroTools.isexpr(lhs, :ref)
                lhs = ref_to_symbolic!(lhs, compiler_state)
                if Symbolics.isequal(lhs, __SKIP__)
                    continue
                end
                tosymbol(lhs) isa Symbol || error("LHS need to be simple.")
            else
                lhs = tosymbolic(lhs)
            end

            variables = find_all_variables(rhs)
            rhs, ref_variables = replace_variables(rhs, variables, compiler_state)
            if !isempty(ref_variables) && Symbolics.isequal(ref_variables[1], __SKIP__)
                continue
            end
            sym_rhs = eval(rhs)

            if haskey(compiler_state.logicalrules, lhs)
                Symbolics.isequal(sym_rhs, compiler_state.logicalrules[lhs]) && continue
                error("Repeated definition for $(lhs)")
            end
            compiler_state.logicalrules[lhs] = sym_rhs
            addednewrules = true
        end
    end
    return addednewrules
end

"""
    replace_variables(rhs, variables, compiler_state)

Replace all the variables in the expression with a symbolic variable.
"""
replace_variables(rhs::Number, variables, compiler_state::CompilerState) = rhs, []
function replace_variables(rhs::Expr, variables, compiler_state::CompilerState)
    ref_variables = []
    replaced_rhs = MacroTools.prewalk(rhs) do sub_expr
        if MacroTools.isexpr(sub_expr, :ref)
            sym_var = ref_to_symbolic!(sub_expr, compiler_state)
            if Symbolics.isequal(sym_var, __SKIP__) # Some index can't be resolved in this generation
                push!(ref_variables, __SKIP__) # Put the SKIP signal in the returned variable vector
                return sub_expr # TODO: might worth writing our own recursive traversal code to support early termination
            end
            push!(ref_variables, sym_var)
            return sym_var
        elseif sub_expr isa Symbol && in(tosymbolic(sub_expr), variables)
            return tosymbolic(sub_expr)
        else
            return sub_expr
        end
    end
    return replaced_rhs, ref_variables
end
function replace_variables(ex::Expr, variables)
    return MacroTools.prewalk(ex) do sub_expr
        if MacroTools.isexpr(sub_expr, :ref)
            sym_var = ref_to_symbolic(sub_expr)
            return sym_var
        elseif sub_expr isa Symbol && in(tosymbolic(sub_expr), variables)
            return tosymbolic(sub_expr)
        else
            return sub_expr
        end
    end
end

"""
    addstochasticrules!(expr, compiler_state::CompilerState)

Process all the stochastic assignments and add them to `CompilerState.stochasticrules`.
"""
function addstochasticrules!(expr::Expr, compiler_state::CompilerState)
    for arg in expr.args
        if arg.head == :(~)
            lhs, rhs = arg.args

            if MacroTools.isexpr(lhs, :ref)
                lhs = ref_to_symbolic!(lhs, compiler_state)
                if Symbolics.isequal(lhs, __SKIP__)
                    error("Exists unresolvable indexing at $arg.")
                end
                tosymbol(lhs) isa Symbol || error("LHS need to be simple.")
            else
                lhs = tosymbolic(lhs)
            end

            if rhs.head == :call
                dist_func = rhs.args[1]
                dist_func in DISTRIBUTIONS || dist_func in (:truncated, :truncated_with_lower, :truncated_with_upper) || 
                    dist_func in (:censored, :censored_with_lower, :censored__with_upper) || error("$dist_func not defined.") 
            else
                error("RHS needs to be a distribution function")
            end

            rhs, ref_variables = find_ref_variables(rhs, compiler_state)
            if !isempty(ref_variables) && Symbolics.isequal(ref_variables[1], __SKIP__)
                error("Exists unresolvable indexing at $arg.")
            end
            variables = find_all_variables(rhs)

            # replace all the variables that can be evaluated to a concrete number
            datavars = Dict{Num, Real}()
            argvars = Num[]
            for var in vcat(variables, ref_variables)
                resolved = resolve(var, compiler_state)
                if resolved isa Number
                    datavars[var] = resolved
                else
                    push!(argvars, var)
                end
            end
            rhs = MacroTools.postwalk(rhs) do sub_expr
                if sub_expr isa Symbol && tosymbolic(sub_expr) in keys(datavars)
                    return datavars[tosymbolic(sub_expr)]
                else
                    return sub_expr
                end
            end

            arguments = map(tosymbol, argvars)
            func_expr = Expr(:(->), Expr(:tuple, arguments...), Expr(:block, rhs))

            if haskey(compiler_state.stochasticrules, lhs) && func_expr != compiler_state.stochasticrules[lhs]
                error("Repeated definition for $(lhs)")
            end
            
            compiler_state.stochasticrules[lhs] = func_expr
        end
    end
end

find_ref_variables(rhs::Number, compiler_state::CompilerState) = rhs, []
function find_ref_variables(rhs::Expr, compiler_state::CompilerState)
    ref_variables = Num[]
    replaced_rhs = MacroTools.prewalk(rhs) do sub_expr
        if MacroTools.isexpr(sub_expr, :ref)
            sym_var = ref_to_symbolic!(sub_expr, compiler_state)
            sym_var = Symbolics.scalarize(sym_var)
            if Symbolics.isequal(sym_var, __SKIP__) # Some index can't be resolved in this generation
                push!(ref_variables, __SKIP__) # Put the SKIP signal in the returned variable vector
                return sub_expr
            end
            if !isempty(size(sym_var))
                sym_var = collect(Iterators.flatten(sym_var))
                ref_variables = vcat(ref_variables, sym_var)
                ret = Meta.parse("[]")
                for var in sym_var
                    push!(ret.args, tosymbol(var))
                end
                return ret
            else
                push!(ref_variables, sym_var)
                return tosymbol(sym_var)
            end
        else
            return sub_expr
        end
    end
    return replaced_rhs, ref_variables
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

scalarize_function_on_array(ex::SymbolicUtils.Term) = scalarize_function_on_array(Symbolics.wrap(ex))
function scalarize_function_on_array(ex::Num)
    ex_val = Symbolics.unwrap(ex)
    if !istree(ex_val) || !isa(ex_val, SymbolicUtils.Term) 
        return ex
    end
    arguments = Symbolics.arguments(ex_val)
    new_ex_val = deepcopy(ex_val)
    
    # check if all symbolic terms has field arguemnts: 2x+3y
    ret = Dict()
    for (i, arg) in enumerate(arguments)
        args = []
        arr = :nothing
        if isa(arg, Array)
            arr = map(Symbolics.wrap, arg)
            args = map(tosymbol, arr)
            new_ex_val = @set new_ex_val.arguments[i] = arr
            ret[arr] = args
        elseif istree(arg)
            new_ex_val = @set new_ex_val.arguments[i] = Symbolics.unwrap(scalarize_function_on_array(Symbolics.wrap(arg))[1])
        else
            continue
        end
    end

    return Symbolics.wrap(new_ex_val), ret
end

function vcat_wo_repeat_elem(v1::Vector, v2::Vector)
    v = deepcopy(v1)
    for elem in v2
        if elem ∉ v
            push!(v, elem)
        end
    end
    return v
end

function tograph(compiler_state::CompilerState)
    # node_name => (default_value, function, node_type)
    to_graph = Dict{Symbol, Tuple{Union{Array{Float64}, Float64}, Function, Symbol}}()

    for key in keys(compiler_state.logicalrules)
        isempty(size(key)) || continue 
        default_value = resolve(key, compiler_state)
        
        if isa(default_value, Real)
            # if the variable can be evaluated into a concrete value, then if it is used
            # somewhere else, the concrete value will be used, otherwise, it is a detached node
            continue
        end

        ex = compiler_state.logicalrules[key]
        # try evaluate the RHS, ideally, this will get ride of all the dependency on data nodes
        ex = resolve(ex, compiler_state)
        ex = Symbolics.scalarize(ex)
        ex, arr_arg = scalarize_function_on_array(ex)
        args = Symbolics.get_variables(ex)
        f_expr = Symbolics.build_function(ex, args...)

        for arr in keys(arr_arg)
            f_expr.args[1].args = vcat_wo_repeat_elem(f_expr.args[1].args, arr_arg[arr])
            f_expr = MacroTools.prewalk(f_expr) do sub_expr
                if MacroTools.isexpr(sub_expr)
                    new_expr = deepcopy(sub_expr)
                    for (i, a) in enumerate(sub_expr.args)
                        if isequal(arr, a)
                            new_expr.args[i] = Expr(:call, :row_major_reshape, Expr(:vect, arr_arg[arr]...), Expr(:tuple, size(arr)...))
                            return new_expr
                        end
                    end
                    return new_expr
                else
                    return sub_expr
                end
            end
        end

        to_graph[tosymbol(key)] = (Float64(0), eval(f_expr), :Logical)
    end

    for key in keys(compiler_state.stochasticrules)
        type = :Stochastic
        default_value = resolve(key, compiler_state)
        if isa(default_value, Union{Integer,Float64})
            type = :Observations
        else
            default_value = 0
        end
        default_value = Float64(default_value)

        func_expr = compiler_state.stochasticrules[key]
        to_graph[tosymbol(key)] =
            (default_value, eval(func_expr), type)
    end

    return to_graph
end

function tograph_w_expr(compiler_state::CompilerState)
    # node_name => (default_value, function, node_type)
    to_graph = Dict{Symbol, Tuple{Union{Array{Float64}, Float64}, Expr, Symbol}}()

    for key in keys(compiler_state.logicalrules)
        isempty(size(key)) || continue 
        default_value = resolve(key, compiler_state)
        
        if isa(default_value, Real)
            # if the variable can be evaluated into a concrete value, then if it is used
            # somewhere else, the concrete value will be used, otherwise, it is a detached node
            continue
        end

        ex = compiler_state.logicalrules[key]
        # try evaluate the RHS, ideally, this will get ride of all the dependency on data nodes
        ex = resolve(ex, compiler_state)
        ex = Symbolics.scalarize(ex)
        ex, arr_arg = scalarize_function_on_array(ex)
        args = Symbolics.get_variables(ex)
        f_expr = Symbolics.build_function(ex, args...)

        for arr in keys(arr_arg)
            f_expr.args[1].args = vcat_wo_repeat_elem(f_expr.args[1].args, arr_arg[arr])
            f_expr = MacroTools.prewalk(f_expr) do sub_expr
                if MacroTools.isexpr(sub_expr)
                    new_x = deepcopy(sub_expr)
                    for (i, a) in enumerate(sub_expr.args)
                        if isequal(arr, a)
                            new_x.args[i] = Expr(:call, :row_major_reshape, Expr(:vect, arr_arg[arr]...), Expr(:tuple, size(arr)...))
                            return new_x
                        end
                    end
                    return new_x
                else
                    return sub_expr
                end
            end
        end

        to_graph[tosymbol(key)] = (Float64(0), f_expr, :Logical)
    end

    for key in keys(compiler_state.stochasticrules)
        type = :Stochastic
        default_value = resolve(key, compiler_state)
        if isa(default_value, Union{Integer,Float64})
            type = :Observations
        else
            default_value = 0
        end
        default_value = Float64(default_value)

        func_expr = compiler_state.stochasticrules[key]
        to_graph[tosymbol(key)] =
            (default_value, func_expr, type)
    end

    return to_graph
end

issimpleexpression(expr) = Meta.isexpr(expr, (:(=), :~))

"""
    refinindices(expr)

Check if all indices in the expression are resolved to concrete numbers.
"""
function refinindices(expr::Expr)::Bool
    exist = true
    MacroTools.prewalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :ref)
            for arg in sub_expr.args
                MacroTools.postwalk(arg) do subsub_expr
                    if Meta.isexpr(subsub_expr, :ref) 
                        exist = false
                    end
                end
            end
        end
        return sub_expr
    end
    return exist
end

"""
    compile_graphppl(model_def, data, initials)

The exported top level function. `compile_graphppl` takes model definition and data and returns a GraphPPL.Model.
"""
function compile_graphppl(; model_def::Expr, data::NamedTuple, initials::NamedTuple) 
    expr = inverselinkfunction(model_def)
    expr = convert_cumulative(expr)
    expr = translate_censoring_expressions(expr)
    expr = translate_truncating_expressions(expr)

    compiler_state = CompilerState()
    addlogicalrules!(data, compiler_state)
    print("Finished reading data.\n")

    while true
        unrollforloops!(expr, compiler_state) ||
            resolveif!(expr, compiler_state) ||
            addlogicalrules!(expr, compiler_state) ||
            break
    end
    print("Finished processing logical assignments.\n")

    addstochasticrules!(expr, compiler_state)
    print("Finished processing stochastic assignments.\n")

    all(issimpleexpression, expr.args) || refinindices(expr) ||
        error("Has unresolvable loop bounds or if conditions.")
    model = tograph(compiler_state)
    print("Finished pre Model-building preparation.\n")

    graphmodel = Model(; model...);
    print("Finish building Model.\n")
    
    for variable in keys(initials)
        if !isempty(size(initials[variable]))
            for i in CartesianIndices(initials[variable])
                isequal(initials[variable][i], missing) && continue
                s = bugs_to_julia("$variable") * "$(collect(Tuple(i)))"
                n = tosymbolic(Meta.parse(s))
                vn = AbstractPPL.VarName(tosymbol(n))
                set_node_value!(graphmodel, vn, initials[variable][i])
            end
        else
            set_node_value!(graphmodel, AbstractPPL.VarName(variable), initials[variable])
        end
    end

    return graphmodel
end

function compile_to_expr(; model_def::Expr, data::NamedTuple, initials::NamedTuple)
    expr = inverselinkfunction(model_def)
    expr = convert_cumulative(expr)
    expr = translate_censoring_expressions(expr)
    expr = translate_truncating_expressions(expr)

    compiler_state = CompilerState()
    addlogicalrules!(data, compiler_state)
    print("Finished reading data.\n")

    while true
        unrollforloops!(expr, compiler_state) ||
            resolveif!(expr, compiler_state) ||
            addlogicalrules!(expr, compiler_state) ||
            break
    end
    print("Finished processing logical assignments.\n")

    addstochasticrules!(expr, compiler_state)
    print("Finished processing stochastic assignments.\n")

    all(issimpleexpression, expr.args) || refinindices(expr) ||
        error("Has unresolvable loop bounds or if conditions.")
    model = tograph_w_expr(compiler_state)

    return model
end
