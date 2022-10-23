using BangBang
using Distributions
using LinearAlgebra
using MacroTools
using Setfield
using Symbolics, SymbolicUtils
using Random

struct CompilerState
    model_def::Expr
    arrays::Dict{Symbol,Symbolics.Arr{Num}}
    logicalrules::Dict
    stochasticrules::Dict
    observations::Dict
end

CompilerState(model_def::Expr) = CompilerState(deepcopy(model_def), Dict{Symbol,Symbolics.Arr{Num}}(), Dict(), Dict(), Dict())

#
# Regularize ASTs to make them easier to work with
#

function cumulative(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = cumulative(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :cdf 
            sub_expr.args[2].args[2] = dist
            return sub_expr
        else
            return sub_expr
        end
    end
end

function density(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = density(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :pdf 
            sub_expr.args[2].args[2] = dist
            return sub_expr
        else
            return sub_expr
        end
    end
end

function deviance(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = deviance(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :logpdf 
            sub_expr.args[2].args[2] = dist
            sub_expr.args[2] = Expr(:call, :*, -2, sub_expr.args[2])
            return sub_expr
        else
            return sub_expr
        end
    end
end

function find_tilde_rhs(expr::Expr, target::Union{Expr, Symbol})
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
    isnothing(dist) && error("Error handling cumulative expression: can't find a stochastic assignment for $target.")
    return dist
end

function linkfunction(expr::Expr)
    expr = MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :link_function)
            sub_expr = Expr(sub_expr.args...)
        end
        return sub_expr
    end

    expr = MacroTools.prewalk(expr) do sub_expr
        if sub_expr isa Expr
            for (i, arg) in enumerate(sub_expr.args)
                if Meta.isexpr(arg, :(~)) && Meta.isexpr(arg.args[1], :call)
                    link_lhs, rhs = arg.args
        
                    link_fun, lhs = link_lhs.args
                    inter_var = String(link_fun) * "(" * String(lhs) * ")" |> Symbol
        
                    splice!(
                        sub_expr.args, 
                        i, 
                        [
                            Expr(:(~), inter_var, rhs),
                            Expr(:(=), inter_var, Expr(:call, link_fun, lhs)), # need this for observation
                            Expr(:(=), lhs, Expr(:call, INVERSE_LINK_FUNCTION[link_fun], inter_var)) # need this for assumption
                        ]
                    )
                end
            end
        end
        return sub_expr
    end

    expr = MacroTools.postwalk(expr) do sub_expr
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

    return expr
end

function censored(expr::Expr)
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

function truncated(expr::Expr)
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

function transform_expr(model_def::Expr)
    return model_def |> linkfunction |> censored |> truncated |> cumulative |> density |> deviance
end

"""
    unroll!(expr, compiler_state)

Unroll all the loops whose loop bounds can be partially evaluated to a constant. 
"""
function unroll!(expr::Expr, compiler_state::CompilerState)
    hasunrolled = false
    while canunroll(expr, compiler_state)
        for (i, arg) in enumerate(expr.args)
            if arg.head == :for
                unrolled = unroll(arg, compiler_state)
                splice!(expr.args, i, unrolled.args)
                hasunrolled = true
                # unroll one loop at a time to avoid complication raised by mutation
                break
            end
        end
    end
    return hasunrolled
end

is_integer(x) = isa(x, Real) && isinteger(x)

function canunroll(expr::Expr, compiler_state::CompilerState)
    for arg in expr.args
        if Meta.isexpr(arg, :for)
            lower_bound, upper_bound = arg.args[1].args[2].args
            lower_bound = resolve(lower_bound, compiler_state.logicalrules)
            upper_bound = resolve(upper_bound, compiler_state.logicalrules)
            is_integer(lower_bound) &&
                is_integer(upper_bound) &&
                return true
        end
    end
    return false
end

function unroll(expr::Expr, compiler_state::CompilerState)
    loop_var = expr.args[1].args[1]
    lower_bound, upper_bound = expr.args[1].args[2].args
    body = expr.args[2]

    lower_bound = resolve(lower_bound, compiler_state.logicalrules)
    upper_bound = resolve(upper_bound, compiler_state.logicalrules)
    if is_integer(lower_bound) && is_integer(upper_bound)
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

                cond = resolve(condition, compiler_state.logicalrules)
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
    tosymbolic(variable)

Return symbolic variable for multiple types of `variable`s. 
"""
tosymbolic(variable::Union{Int, AbstractFloat}) = Num(variable)
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

"""
    beautify_ref_symbol(s)

`Symbolics.tosymbol` return `getindex(g, 1)` for `g[1]`. This function beautifies it to `g[1]`.
"""
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
        if index isa Expr || (index isa Symbol && index != :(:))
            if Meta.isexpr(index, :call) && index.args[1] == :(:)
                lb = resolve(index.args[2], compiler_state.logicalrules) 
                ub = resolve(index.args[3], compiler_state.logicalrules)
                if lb isa Real && ub isa Real
                    indices[i].args[2] = lb
                    indices[i].args[3] = ub
                else
                    return __SKIP__
                end
            end

            resolved_index = resolve(tosymbolic(index), compiler_state.logicalrules)
            if !isa(resolved_index, Union{Real, UnitRange})
                return __SKIP__
            end 

            if isa(resolved_index, Real) 
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

# https://github.com/JuliaSymbolics/SymbolicUtils.jl/blob/a42082ac90f951f677ce1e2a91cd1a0ddd4306c6/src/substitute.jl#L1
# modified to handle `missing` data
# TODO: find a way to achieve the same functionality without overwriting SymbolicUtils.substitute
function SymbolicUtils.substitute(expr, dict; fold=true)
    haskey(dict, expr) && return ismissing(dict[expr]) ? expr : dict[expr]

    if istree(expr)
        op = substitute(operation(expr), dict; fold=fold)
        if fold
            canfold = !(op isa SymbolicUtils.Symbolic)
            args = map(SymbolicUtils.unsorted_arguments(expr)) do x
                x′ = substitute(x, dict; fold=fold)
                canfold = canfold && !(x′ isa SymbolicUtils.Symbolic)
                x′
            end
            canfold && return ismissing(op(args...)) ? expr : op(args...)
            args
        else
            args = map(x->substitute(x, dict, fold=fold), SymbolicUtils.unsorted_arguments(expr))
        end

        SymbolicUtils.similarterm(expr,
                    op,
                    args,
                    SymbolicUtils.symtype(expr);
                    metadata=SymbolicUtils.metadata(expr))
    else
        expr
    end
end

"""
    resolve(variable, compiler_state)

Partially evaluate the variable in the environment defined by compiler_state.
"""
resolve(variable::Distributions.Distribution, rules::Dict) = variable
function resolve(variable, rules::Dict)
    resolved_variable = symbolic_eval(tosymbolic(variable), rules)
    return Symbolics.unwrap(resolved_variable)
end
function symbolic_eval(variable, rules::Dict)
    if variable isa Symbolics.Arr{Num}
        variable = Symbolics.scalarize(variable)
    end
    partial_trace = []
    evaluated = substitute(variable, rules)

    let e = Symbolics.toexpr(evaluated) 
        if Meta.isexpr(e, :call) && in(Symbol(e.args[1]), TRACED_FUNCTIONS) # if symbolically traced, can be more general, only handle :exp now
            func = e.args[1]
            nargs = size(e.args)[1] - 1
            args = arguments(Symbolics.unwrap(evaluated))
            resolved_args = []
            for i in 1:nargs
                arg = Symbolics.wrap(args[i])
                resolved_arg = symbolic_eval(arg, rules)
                push!(resolved_args, resolved_arg)
            end
            return func(resolved_args...)
        end
    end

    try_evaluated = substitute(evaluated, rules)
    try_evaluated isa Array || push!(partial_trace, try_evaluated)

    while !Symbolics.isequal(evaluated, try_evaluated)
        evaluated = try_evaluated
        try_evaluated = substitute(try_evaluated, rules)
        try_evaluated isa Array || try_evaluated in partial_trace && break # avoiding infinite loop
    end

    return try_evaluated
end
symbolic_eval(variable::UnitRange{Int64}, rules::Dict) = variable # Special case for array range

Base.isequal(::SymbolicUtils.Symbolic, ::Missing) = false

Base.in(key::Num, vs::Vector) = any(broadcast(Symbolics.isequal, key, vs))

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
    for (i, arg) in enumerate(expr.args)
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
            expr.args[i] = Expr(:deleted) # avoid repeat evaluation
            addednewrules = true
        end
    end
    return addednewrules
end

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
                    dist_func in (:censored, :censored_with_lower, :censored__with_upper) || dist_func in USER_DISTRIBUTIONS || 
                    error("Distribution $dist_func not defined.") 
            else
                error("RHS needs to be a distribution function")
            end

            variables = find_all_variables(rhs)
            rhs, ref_variables = replace_variables(rhs, variables, compiler_state)
            if !isempty(ref_variables) && Symbolics.isequal(ref_variables[1], __SKIP__)
                continue
            end
            sym_rhs = eval(rhs)
            
            if sym_rhs isa Distributions.Distribution
                nothing
            end

            if haskey(compiler_state.stochasticrules, lhs)
                # Symbolics.isequal(sym_rhs, compiler_state.stochasticrules[lhs]) && continue
                error("Repeated definition for $(lhs)")
            end
            
            if haskey(compiler_state.logicalrules, lhs)
                if !isa(resolve(lhs, compiler_state.logicalrules), Real)
                    error("A stochastic variable cannot be used as LHS of logical assignments unless it's an observation.")
                end
            end
            compiler_state.stochasticrules[lhs] = sym_rhs
        end
    end
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
                push!(ref_variables, __SKIP__) 
                return sub_expr
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

find_all_variables(rhs::Number) = []
find_all_variables(rhs::Symbol) = Base.occursin("[", string(rhs)) ? [] : rhs
function find_all_variables(rhs::Expr)
    variables = []
    recursive_find_variables(rhs, variables)
    return map(tosymbolic, variables)
end

function recursive_find_variables(expr::Expr, variables::Vector{Any})
    MacroTools.prewalk(expr) do sub_expr
        if MacroTools.isexpr(sub_expr, :call)
            for arg in sub_expr.args[2:end] # only touch the arguments
                if arg isa Symbol && !Base.occursin("[", string(arg))
                    push!(variables, arg)
                    continue
                end
                arg isa Expr && recursive_find_variables(arg, variables)
            end
        end
    end
end

function extract_observations!(compiler_state::CompilerState)
    for k in keys(compiler_state.stochasticrules)
        resolved_val = resolve(k, compiler_state.logicalrules)
        if resolved_val isa Real
            compiler_state.observations[k] = resolved_val
            if k in keys(compiler_state.logicalrules)
                delete!(compiler_state.logicalrules, k)
            elseif occursin("[", string(tosymbol(k)))
                if k in keys(compiler_state.logicalrules)
                    delete!(compiler_state.logicalrules, k)
                    break
                end
                var = k.val.arguments[1].name
                sym_arr = compiler_state.arrays[var]
                @assert haskey(compiler_state.logicalrules, sym_arr) "Can't find the variable $k in the logical rules."
                index = Tuple(Meta.parse(string(tosymbol(k))).args[2:end])
                setindex!!(compiler_state.logicalrules[sym_arr], missing, index...)
            end
        end
    end
end

"""
    scalarize(ex)

Convert symbolic arrays in symbolic expressions to arrays of `Num`. Also return the mapping the array of `Num`
to an array of Symbols.

```julia-repo
julia> using Symbolics; @register_symbolic foo(x::Vector)

julia> @variables x[1:3]; Symbolics.scalarize(foo(x[1:3]))
foo(SymbolicUtils.Term{Real, Nothing}[x[1], x[2], x[3]])

julia> using SymbolicPPL; SymbolicPPL.scalarize(foo(x[1:3]))
(foo(Num[x[1], x[2], x[3]]), Dict{Any, Any}(Num[x[1], x[2], x[3]] => [Symbol("x[1]"), Symbol("x[2]"), Symbol("x[3]")]))
```
"""
function scalarize(ex::Num, compiler_state::CompilerState)
    istree(Symbolics.unwrap(ex)) || return ex, Dict()
    ex_val = Symbolics.unwrap(Symbolics.scalarize(ex))
    if !isa(ex_val, SymbolicUtils.Term) 
        ex_val = SymbolicUtils.toterm(ex_val)
    end
    arguments = Symbolics.arguments(ex_val)
    new_ex_val = deepcopy(ex_val)
    
    sub_dict = Dict()
    for (i, arg) in enumerate(arguments)
        if isa(arg, Array)
            args = Set{Symbol}()
            new_arg = Array{Num}(undef, size(arg))
            for j in eachindex(arg)
                elem = symbolic_eval(Symbolics.wrap(arg[j]), compiler_state.logicalrules)
                new_arg[j], r  = scalarize(elem, compiler_state)
                sub_dict = merge(sub_dict, r)
            end
            new_arg = reduce(vcat, new_arg)
            for a in new_arg
                vars = Symbolics.get_variables(a)
                for v in vars
                    @assert v in keys(compiler_state.stochasticrules)
                    push!(args, tosymbol(v))
                end
            end
            new_ex_val = @set new_ex_val.arguments[i] = new_arg
            if new_arg isa Array{Num}
                sub_dict[new_arg] = (args, size(arg))
            end
        elseif istree(arg)
            new_arg, r = scalarize(Symbolics.wrap(arg), compiler_state)
            new_ex_val = @set new_ex_val.arguments[i] = Symbolics.unwrap(new_arg)
            sub_dict = merge(sub_dict, r)
        else
            continue
        end
    end

    return Symbolics.wrap(new_ex_val), sub_dict
end
scalarize(ex, ::CompilerState) = ex, Dict()

function gen_output(compiler_state::CompilerState)
    pregraph = Dict()
    for key in keys(compiler_state.stochasticrules)
        ex = symbolic_eval(compiler_state.stochasticrules[key], compiler_state.logicalrules)
        ex, sub_dict = scalarize(ex, compiler_state)
        args = Symbolics.get_variables(ex)
        f_expr = Base.remove_linenums!(Symbolics.build_function(ex, args...))

        while !isempty(sub_dict)
            for arr in keys(sub_dict)
                f_expr.args[1].args = collect(union(Set(f_expr.args[1].args), Set(sub_dict[arr][1])))
                f_expr = MacroTools.postwalk(f_expr) do sub_expr
                    if isequal(sub_expr, arr)
                        if length(sub_dict[arr][2]) == 2 && (sub_dict[arr][2][1] == 1 || sub_dict[arr][2][2] == 1)
                            sub_expr = Expr(:vect, (Symbolics.toexpr.(arr))...)
                        else
                            sub_expr = Expr(:call, :rreshape, Expr(:vect, (Symbolics.toexpr.(arr))...), Expr(:tuple, sub_dict[arr][2]...))
                        end
                        delete!(sub_dict, arr)
                    end
                    return sub_expr
                end |> getindex_to_ref |> MacroTools.flatten |> MacroTools.resyntax
            end
        end

        if !isempty(compiler_state.observations)
            if haskey(compiler_state.observations, key)
                value = compiler_state.observations[key]
                isdata = true
            else
                value = missing
                isdata = false
            end
        else
            value = resolve(key, compiler_state.logicalrules)
            isdata = isa(value, Real)
            value = isdata ? value : missing
        end

        pregraph[tosymbol(key)] = (value, f_expr, isdata)
    end
    return pregraph
end

function getindex_to_ref(expr)
    return MacroTools.prewalk(expr) do sub_expr
        # if MacroTools.@capture(sub_ex, getindex(name_, size__))
        if MacroTools.isexpr(sub_expr, :call) && sub_expr.args[1] == getindex
            sub_expr.head = :ref
            sub_expr.args = sub_expr.args[2:end]
            sub_expr = tosymbol(ref_to_symbolic(sub_expr))
        end
        return sub_expr
    end
end

# Bugs in SymbolicUtils.jl
# Fixed at: https://github.com/JuliaSymbolics/SymbolicUtils.jl/pull/471
# Not in the latest release yet.
function SymbolicUtils.toterm(t::SymbolicUtils.Add{T}) where T
    args = Any[t.coeff, ]
    for (k, coeff) in t.dict
        push!(args, coeff == 1 ? k : SymbolicUtils.Term{T}(*, [coeff, k]))
    end
    SymbolicUtils.Term{T}(+, args)
end

function refinindices(expr, compiler_state)
    MacroTools.prewalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :ref)
            for arg in sub_expr.args[2:end]
                Meta.isexpr(arg, :ref) &&
                    Symbolics.isequal(ref_to_symbolic!(arg, compiler_state), __SKIP__) && 
                    error("$sub_expr's index $arg can't be resolved.")
                refinindices(arg, compiler_state)
            end
        end
        return sub_expr
    end
end

function is_fully_unrolled(expr, compiler_state::CompilerState)
    # check if any loop or if remains
    for sub_expr in expr.args
        Meta.isexpr(sub_expr, (:~, :(=), :deleted)) ||
            error("$sub_expr can't be resolved.")
    end

    # check if all array indices are resolvable
    refinindices(expr, compiler_state)
end

function check_expr(expr, compiler_state::CompilerState)
    is_fully_unrolled(expr, compiler_state)

    # check if there exist using observed stochastic variables for loop bounds or indexing
    expr_copy = deepcopy(compiler_state.model_def)
    while true
        unroll!(expr_copy, compiler_state) ||
        resolveif!(expr_copy, compiler_state) ||
        break
    end
    try 
        is_fully_unrolled(expr_copy, compiler_state)
    catch e
        error("Check the model definition for using observed stochastic variables as loop bounds or indexing.")
    end
end

"""
    compile(model_def, data, target)

Compile the model definition `model_def` with data `data` and target `target`.

# Arguemnts
- `model_def`: the Julia Expr object returned from `@bugsast` or `bugsmodel`.
- `data`: data and model prameters.
- `target`: one of `:DynamicPPL`, `:IR`, or `:Graph`. 
"""
function compile(model_def::Expr, data::NamedTuple, target::Symbol) 
    @assert target in [:DynamicPPL, :IR, :Graph] "target must be one of [:DynamicPPL, :IR, :Graph]"
    
    expr = transform_expr(model_def)

    compiler_state = CompilerState(expr)
    addlogicalrules!(data, compiler_state)
    while true
        unroll!(expr, compiler_state) ||
            resolveif!(expr, compiler_state) ||
            addlogicalrules!(expr, compiler_state) ||
            break
    end

    addstochasticrules!(expr, compiler_state)
    extract_observations!(compiler_state)

    check_expr(expr, compiler_state)

    target == :IR && return compiler_state

    g = to_metadigraph(gen_output(compiler_state))
    target == :Graph && return g
    target == :DynamicPPL && return todppl(g)
end