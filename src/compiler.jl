struct CompilerState
    model_def::Expr # original model definition
    arrays::Dict{Symbol,Symbolics.Arr{Num}}
    data_arrays::Dict{Symbol,Symbolics.Arr{Num}} # keep track of data arrays, the size of these arrays are not inferred and not allowed to change
    logicalrules::Dict
    stochasticrules::Dict
    observations::Dict
    multivariate_variables::Dict # Map renamed multivariate variables to their original symbolic arrays
end

function CompilerState(model_def::Expr) 
    return CompilerState(
        deepcopy(model_def), 
        Dict{Symbol,Symbolics.Arr{Num}}(),
        Dict{Symbol,Symbolics.Arr{Num}}(),
        Dict(), 
        Dict(), 
        Dict(),
        Dict()
    )
end

# Regarding the correctness of the unrolling approach:
# - BUGS doesn't allow repeated assignments, loop bounds are defined outside the loop
# - assignments describe edges, finite graph indicated finite amount of assignments
# Two loops with mutually dependent loop bounds (loop bounds depend on variable defined in another loop) can not be unrolled. 
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
                # unroll one loop at a time to avoid complication caused by mutation
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


function ref_to_symbolic end

function ref_to_symbolic! end

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

addlogicalrules!(data::NamedTuple, compiler_state::CompilerState, skip_colon=true) =
    addlogicalrules!(Dict(pairs(data)), compiler_state)
function addlogicalrules!(data::Dict, compiler_state::CompilerState, skip_colon=true)
    for (key, value) in data
        if value isa Number
            compiler_state.logicalrules[tosymbolic(key)] = value
        elseif value isa Array
            sym_array = create_symbolic_array(key, collect(size(value)))
            compiler_state.logicalrules[sym_array] = value
            compiler_state.data_arrays[key] = sym_array
        else
            error("Value type not supported.")
        end
    end
end
function addlogicalrules!(expr::Expr, compiler_state::CompilerState, skip_colon=true)
    addednewrules = false
    for (i, arg) in enumerate(expr.args)
        if arg.head == :(=)
            lhs, rhs = arg.args

            if MacroTools.isexpr(lhs, :ref)
                if lhs.args[1] in keys(compiler_state.data_arrays)
                    error("Elements of data arrays can not be re-assigned.")
                end
                lhs = ref_to_symbolic!(lhs, compiler_state, skip_colon)
                if Symbolics.isequal(lhs, __SKIP__)
                    continue
                end

                if lhs isa Symbolics.Arr
                    elems = Symbolics.scalarize(lhs)
                    renamed_lhs = create_symbolic_variable(tosymbol(lhs)) 
                    # change the lhs to a scalar, this scalar will be of array type during inference
                    compiler_state.multivariate_variables[renamed_lhs] = lhs # keep the symbolic array for initialization
                    lhs = renamed_lhs
                    for i in eachindex(elems)
                        compiler_state.logicalrules[elems[i]] = get_index(lhs, i)
                    end
                end

                @assert tosymbol(lhs) isa Symbol "LHS need to be simple."
            else
                lhs = tosymbolic(lhs)
            end

            variables = find_all_variables(rhs)
            rhs, ref_variables = replace_variables(rhs, variables, compiler_state, skip_colon)
            if !isempty(ref_variables) && Symbolics.isequal(ref_variables[1], __SKIP__)
                continue
            end
            sym_rhs = eval(rhs)

            if haskey(compiler_state.logicalrules, lhs)
                Symbolics.isequal(sym_rhs, compiler_state.logicalrules[lhs]) && continue
                error("Repeated definition for $(lhs)")
            end
            compiler_state.logicalrules[lhs] = sym_rhs
            expr.args[i] = Expr(:processed) # avoid repeat evaluation
            addednewrules = true
        end
    end
    return addednewrules
end

function addstochasticrules!(expr::Expr, compiler_state::CompilerState, skip_colon=true)
    addednewrules = false
    for (i, arg) in enumerate(expr.args)
        if arg.head == :(~)
            lhs, rhs = arg.args

            if Meta.isexpr(lhs, :call)
                f = lhs.args[1]
                if f in keys(INVERSE_LINK_FUNCTION)
                    lhs_var = lhs.args[2]
                    lhs = String(f) * "(" * String(lhs_var) * ")" |> Symbol
                    if resolve(tosymbolic(lhs_var), compiler_state.logicalrules) isa Real # observation
                        addlogicalrules!(
                            Expr(:block, Expr(:(=), lhs, Expr(:call, f, lhs_var))),
                            compiler_state
                        )
                    else
                        addlogicalrules!(
                            Expr(:block, Expr(:(=), lhs_var, Expr(:call, INVERSE_LINK_FUNCTION[f], lhs))),
                            compiler_state
                        )
                    end
                else
                    error("Link function $f not supported.")
                end
            end

            if MacroTools.isexpr(lhs, :ref)
                lhs = ref_to_symbolic!(lhs, compiler_state, skip_colon)
                if Symbolics.isequal(lhs, __SKIP__)
                    continue
                end

                if lhs isa Symbolics.Arr
                    elems = Symbolics.scalarize(lhs)
                    renamed_lhs = create_symbolic_variable(tosymbol(lhs)) 
                    # change the lhs to a scalar, this scalar will be of array type during inference
                    compiler_state.multivariate_variables[renamed_lhs] = lhs # keep the symbolic array for initialization
                    lhs = renamed_lhs
                    for i in eachindex(elems)
                        compiler_state.logicalrules[elems[i]] = get_index(lhs, i)
                    end
                end

                @assert isa(tosymbol(lhs), Symbol) "LHS need to be simple."
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
            rhs, ref_variables = replace_variables(rhs, variables, compiler_state, skip_colon)
            if !isempty(ref_variables) && Symbolics.isequal(ref_variables[1], __SKIP__)
                continue
            end
            sym_rhs = eval(rhs)
            
            if sym_rhs isa Distributions.Distribution
                nothing
            end

            if haskey(compiler_state.stochasticrules, lhs)
                error("Repeated definition for $(lhs)")
            end
            
            if haskey(compiler_state.logicalrules, lhs)
                if !isa(resolve(lhs, compiler_state.logicalrules), Real)
                    # Stochastic variables used for indices of the LHS is not allowed.
                    error("A stochastic variable cannot be used as LHS of logical assignments unless it's an observation.")
                end
            end
            compiler_state.stochasticrules[lhs] = sym_rhs
            addednewrules = true
            expr.args[i] = Expr(:stoch_processed)
        end
    end
    
    return addednewrules
end

"""
    replace_variables(rhs, variables, compiler_state)

Replace all the variables in the expression with a symbolic variable.
"""
replace_variables(rhs::Number, variables, compiler_state::CompilerState, skip_colon=true) = rhs, []
function replace_variables(rhs::Expr, variables, compiler_state::CompilerState, skip_colon=true)
    canresolve = true
    ref_variables = []
    replaced_rhs = MacroTools.prewalk(rhs) do sub_expr
        if MacroTools.isexpr(sub_expr, :ref)
            sym_var = ref_to_symbolic!(sub_expr, compiler_state, skip_colon)
            if Symbolics.isequal(sym_var, __SKIP__) # Some index can't be resolved in this generation
                canresolve = false 
            end
            push!(ref_variables, sym_var)
            return sym_var
        elseif sub_expr isa Symbol && in(tosymbolic(sub_expr), variables)
            return tosymbolic(sub_expr)
        else
            return sub_expr
        end
    end
    return replaced_rhs, canresolve ? ref_variables : [__SKIP__, ]
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
            for arg in sub_expr.args[2:end] # only search through the arguments
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
                sym_arr = compiler_state.data_arrays[var]
                @assert haskey(compiler_state.logicalrules, sym_arr) "Can't find the variable $k in the logical rules."
                index = Tuple(Meta.parse(string(tosymbol(k))).args[2:end])
                # potentially modify the referenced array, BangBang version should avoid this problem
                setindex!!(compiler_state.logicalrules[sym_arr], missing, index...)
            end
        end
    end
end

# TODO: Alternatively, can make the first return item a gensym, so later equality check is cheaper.
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
                    # make sure the arguments of a node function are other stochastic variables
                    # this also implicitly checks that all array indexings appear on the RHS also appear on the LHS
                    if !haskey(compiler_state.stochasticrules, v)
                        e = Symbolics.toexpr(v)
                        e isa Symbol && error("$v should be a stochastic variable.")
                        # then v is an array indexing
                        @assert e.head == :call && e.args[1] == getindex
                        find_match = false
                        for k in keys(compiler_state.stochasticrules)
                            !isa(k, Symbolics.Arr) && continue
                            k_e = Symbolics.toexpr(k)
                            if k_e.args[2] == e.args[2]
                                find_match = true
                                break
                            end
                        end
                        !find_match && error("The array indexing $v should be a stochastic variable.")
                    end
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
                    if isequal(sub_expr, arr) # this equality check can be expensive, as it potentially requries comparing two type-unstable arrays
                        if length(sub_dict[arr][2]) == 2 && (sub_dict[arr][2][1] == 1 || sub_dict[arr][2][2] == 1)
                            sub_expr = Expr(:vect, (Symbolics.toexpr.(arr))...)
                        else
                            sub_expr = Expr(:call, :rreshape, Expr(:vect, (Symbolics.toexpr.(arr))...), Expr(:tuple, sub_dict[arr][2]...))
                        end
                        delete!(sub_dict, arr)
                    end
                    return sub_expr
                end |> getindex_to_ref |> MacroTools.resyntax 
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

process_initializations(inits::NamedTuple, pre_graph, compiler_state::CompilerState) = 
    process_initializations(Dict(pairs(inits)), pre_graph, compiler_state)
function process_initializations(inits::Dict, pre_graph, compiler_state::CompilerState)
    # read initlization values
    initilizations = Dict()
    for (key, value) in inits
        if value isa Number
            @assert !occursin("[", string(key)) "Initializations of single elements of arrays not supported, initialize the whole array instead."
            @assert haskey(pre_graph, key) "The variable $key is not a stochastic variable."
            @assert !pre_graph[key][3] "The variable $key is an observed variable, initialization is not supported."
            initilizations[tosymbolic(key)] = value
        elseif value isa Array
            @assert haskey(compiler_state.arrays, key) || haskey(compiler_state.data_arrays, key) "The variable $key is not an array in the model definition."
            @assert size(value) == size(compiler_state.arrays[key]) || size(value) == size(compiler_state.data_arrays[key]) 
                "The size of the initialization of $key does not match the size of the array."
            sym_array = create_symbolic_array(key, collect(size(value)))   
            initilizations[sym_array] = value
        else
            error("Value type not supported.")
        end
    end

    # produce output
    ret = Dict()
    for key in keys(compiler_state.stochasticrules)
        if haskey(compiler_state.multivariate_variables, key)
            let r = symbolic_eval(compiler_state.multivariate_variables[key], initilizations)
                @assert r isa Array 
                rr = similar(r, Any)
                for (i, x) in enumerate(r)
                    let xx = Symbolics.unwrap(x)
                        if xx isa Number
                            rr[i] = xx
                        else
                            rr[i] = missing
                        end
                    end
                end
                if !all(ismissing, rr)
                    ret[tosymbol(key)] = rr
                end
            end
        else
            let r = resolve(key, initilizations)
                if !Symbolics.isequal(r, key)
                    ret[tosymbol(key)] = r
                end
            end
        end
    end

    return ret
end

function getindex_to_ref(expr)
    return MacroTools.prewalk(expr) do sub_expr
        if MacroTools.isexpr(sub_expr, :call) && sub_expr.args[1] == getindex
            sub_expr.head = :ref
            sub_expr.args = sub_expr.args[2:end]
            sub_expr = tosymbol(ref_to_symbolic(sub_expr))
        end
        return sub_expr
    end
end

function refinindices(expr, compiler_state)
    MacroTools.prewalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :ref)
            for arg in sub_expr.args[2:end]
                if Meta.isexpr(arg, :ref) 
                    if !isa(resolve(arg, compiler_state.logicalrules), Real)
                        error("$sub_expr's index $arg can't be resolved.")
                    end
                end
                refinindices(arg, compiler_state)
            end
        end
        return sub_expr
    end
end

function check_expr(compiler_state::CompilerState)
    expr = deepcopy(compiler_state.model_def)
    while true
        unroll!(expr, compiler_state) ||
        resolveif!(expr, compiler_state) ||
        break
    end

    unresolved_exprs = [arg for arg in expr.args if !Meta.isexpr(arg, (:~, :(=)))]
    if !isempty(unresolved_exprs)
        err_msg = IOBuffer()
        for arg in expr.args
            println(err_msg, "$arg can't be resolved. ")
        end
        error(String(take!(err_msg)))
    end  

    refinindices(expr, compiler_state)
end


"""
    compile(model_def, data, target)

Compile the model definition `model_def` with data `data` and target `target`.

# Arguemnts
- `model_def`: the Julia Expr object returned from `@bugsast` or `bugsmodel`.
- `data`: data and model prameters.
- `target`: one of `:DynamicPPL`, `:IR`, or `:Graph`. 
"""
function compile(model_def::Expr, data::NamedTuple, target::Symbol, inits=nothing) 
    @assert target in [:DynamicPPL, :IR, :Graph, ] "target must be one of [:DynamicPPL, :IR, :Graph]"
    
    expr = transform_expr(model_def)

    compiler_state = CompilerState(expr)
    addlogicalrules!(data, compiler_state)
    while true    
        while true
            unroll!(expr, compiler_state) ||
                resolveif!(expr, compiler_state) ||
                addlogicalrules!(expr, compiler_state) ||
                addstochasticrules!(expr, compiler_state) || 
                break
        end
        # leave expressions with colon indexing to the last
        addlogicalrules!(expr, compiler_state, false) || break
    end
    addstochasticrules!(expr, compiler_state, false)

    extract_observations!(compiler_state)

    @assert all(x->Meta.isexpr(x, (:processed, :stoch_processed)), expr.args) "Some expressions are not processed."

    # `check_expr` will try to unroll the origianl expr again to detect to test 
    # using observed stochastic variables as loop bounds or indexing.
    check_expr(compiler_state)

    target == :IR && return compiler_state

    pre_graph = gen_output(compiler_state)
    g = tograph(pre_graph)
    target == :Graph && return g
    
    return todppl(g) # target == :DynamicPPL
end
