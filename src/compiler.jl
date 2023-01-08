struct CompilerState
    """ Original model definition """
    model_def::Expr
    """ Arrays defined in the model definition """
    arrays::Dict{Symbol,Symbolics.Arr{Num}}
    """ Data arrays, sizes are not inferred, assignments to array elements are not permitted """
    data_arrays::Dict{Symbol,Symbolics.Arr{Num}}
    logicalrules::Dict
    stochasticrules::Dict
    observations::Dict
    """ Map of multivariate variables to their original symbolic arrays """
    multivariate_variables::Dict
end

CompilerState(model_def::Expr) = CompilerState(deepcopy(model_def), Dict{Symbol,Symbolics.Arr{Num}}(), Dict{Symbol,Symbolics.Arr{Num}}(), Dict(), Dict(), Dict(), Dict())

# Regarding the correctness of the unrolling approach:
# - BUGS doesn't allow repeated assignments, loop bounds are defined outside the loop
# - assignments describe edges, finite graph indicated finite amount of assignments
# Two loops with mutually dependent loop bounds (loop bounds depend on variable defined in another loop) can not be unrolled. 
"""
    unroll!(expr, compiler_state)

Unroll all the loops whose loop bounds can be partially evaluated to a constant. Return a boolean indicating whether the expression has been modified.
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
        throw(ArgumentError("Loop bounds need to be integers."))
    else
        # if loop bounds contain variables that can't be partial evaluated at this moment
        return expr
    end
end

"""
    resolveif!(expr, compiler_state)

Try to resolve the condition of the `if` statement. If condition is true, hoist out the consequence; 
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
 
Unwrap the result of `symbolic_eval` so that the return value of type `Int` or `Float` instead of symbolic type.
"""
resolve(variable::Distributions.Distribution, rules::Dict) = variable
function resolve(variable, rules::Dict)
    resolved_variable = symbolic_eval(tosymbolic(variable), rules)
    return Symbolics.unwrap(resolved_variable)
end

"""
    symbolic_eval(variable, rules)

Repeatedly evaluate variable with `Symbolics.substitute` until the variable is not changed.
"""
function symbolic_eval(variable, rules::Dict)
    if variable isa Symbolics.Arr{Num}
        variable = Symbolics.scalarize(variable)
    end
    partial_trace = []
    evaluated = substitute(variable, rules)

    # handle traced functions: recursively symbolic_eval the arguments
    let e = Symbolics.toexpr(evaluated)
        if Meta.isexpr(e, :call) && in(Symbol(e.args[1]), TRACED_FUNCTIONS)
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
symbolic_eval(variable::UnitRange{Int64}, rules::Dict) = variable

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
    new_rules_added = false
    for (i, arg) in enumerate(expr.args)
        if arg.head == :(=)
            lhs, rhs = arg.args
            @assert !haskey(compiler_state.logicalrules, lhs) error("$arg is a repeated definition for $(lhs)")

            if MacroTools.isexpr(lhs, :ref)
                @assert !haskey(compiler_state.data_arrays, lhs.args[1]) "$(lhs.args[1]) is data array element, elements of data arrays can not be re-assigned."
                lhs = ref_to_symbolic!(lhs, compiler_state, skip_colon)
                isskip(lhs) && continue
                if lhs isa Symbolics.Arr
                    # multivariate functions
                    elems = Symbolics.scalarize(lhs)
                    renamed_lhs = create_symbolic_variable(tosymbol(lhs))
                    # change the lhs to a scalar, this scalar will be of array type during inference
                    compiler_state.multivariate_variables[renamed_lhs] = lhs # keep the symbolic array for initialization
                    lhs = renamed_lhs
                    for i in eachindex(elems)
                        compiler_state.logicalrules[elems[i]] = get_index(lhs, i)
                    end
                end
            else
                lhs = tosymbolic(lhs)
            end

            rhs = replace_variables!(rhs, compiler_state, skip_colon)
            isskip(rhs) && continue
            compiler_state.logicalrules[lhs] = eval(rhs)
            expr.args[i] = Expr(:logical_processed) # avoid repeat evaluation
            new_rules_added = true
        end
    end
    return new_rules_added
end

function addstochasticrules!(expr::Expr, compiler_state::CompilerState, skip_colon=true)
    new_rules_added = false
    for (i, arg) in enumerate(expr.args)
        if arg.head == :(~)
            lhs, rhs = arg.args

            if Meta.isexpr(lhs, :call)
                f = lhs.args[1]
                @assert f in keys(INVERSE_LINK_FUNCTION) "Link function $f not supported."

                lhs_var = lhs.args[2]
                lhs = String(f) * "(" * String(lhs_var) * ")" |> Symbol
                if resolve(tosymbolic(lhs_var), compiler_state.logicalrules) isa Real # observation
                    addlogicalrules!(Expr(:block, Expr(:(=), lhs, Expr(:call, f, lhs_var))), compiler_state)
                else
                    addlogicalrules!(Expr(:block, Expr(:(=), lhs_var, Expr(:call, INVERSE_LINK_FUNCTION[f], lhs))), compiler_state)
                end
                lhs = tosymbolic(lhs)
            elseif MacroTools.isexpr(lhs, :ref)
                lhs = ref_to_symbolic!(lhs, compiler_state, skip_colon)
                isskip(lhs) && continue
                if lhs isa Symbolics.Arr
                    # multivariate distributions
                    elems = Symbolics.scalarize(lhs)
                    renamed_lhs = create_symbolic_variable(tosymbol(lhs))
                    # change the lhs to a scalar, this scalar will be of array type during inference
                    compiler_state.multivariate_variables[renamed_lhs] = lhs # keep the symbolic array for initialization
                    lhs = renamed_lhs
                    for i in eachindex(elems)
                        compiler_state.logicalrules[elems[i]] = get_index(lhs, i)
                    end
                end
            else
                lhs = tosymbolic(lhs)
            end
            @assert !haskey(compiler_state.stochasticrules, lhs) "Repeated definition for $(lhs)"
            @assert !haskey(compiler_state.logicalrules, lhs) || isa(resolve(lhs, compiler_state.logicalrules), Real) "A stochastic variable cannot be used as LHS of logical assignments unless it's an observation."
            @assert rhs.head == :call "RHS needs to be a distribution function"
            @assert rhs.args[1] in vcat(DISTRIBUTIONS, USER_DISTRIBUTIONS, [:truncated, :truncated_with_lower, :truncated_with_upper, :censored, :censored_with_lower, :censored__with_upper]) "Distribution $dist_func not defined."

            rhs = replace_variables!(rhs, compiler_state, skip_colon)
            isskip(rhs) && continue

            compiler_state.stochasticrules[lhs] = eval(rhs)
            expr.args[i] = Expr(:stoch_processed)
            new_rules_added = true
        end
    end
    return new_rules_added
end

"""
    replace_variables(rhs, variables, compiler_state[, skip_colon])

Replace all the variables in the expression with a symbolic variable. Possibly mutate compiler_state by calling `ref_to_symbolic`.
"""
replace_variables!(rhs::Number, compiler_state::CompilerState, skip_colon=true) = rhs, []
function replace_variables!(rhs::Expr, compiler_state::CompilerState, skip_colon=true)
    skip = false
    f_symbols = find_functions(rhs)
    replaced_rhs = MacroTools.prewalk(rhs) do sub_expr
        if MacroTools.isexpr(sub_expr, :ref)
            sym_var = ref_to_symbolic!(sub_expr, compiler_state, skip_colon)
            isskip(sym_var) && (skip = true)
            sub_expr = sym_var
        elseif isa(sub_expr, Symbol) && !in(sub_expr, f_symbols)
            sub_expr = tosymbolic(sub_expr)
        end
        return sub_expr
    end
    return skip ? __SKIP__ : replaced_rhs
end

function find_functions(expr::Expr)
    functions = Set{Symbol}()
    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.isexpr(sub_expr, :call)
            push!(functions, sub_expr.args[1])
        end
        return sub_expr
    end
    return functions
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
                new_arg[j], r = scalarize(elem, compiler_state)
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

function gen_f_expr(compiler_state, var)
    ex = symbolic_eval(var, compiler_state.logicalrules)
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
            end |> getindex_to_ref
        end
    end

    return f_expr |> unresolve |> MacroTools.resyntax
end

# Symbolics.jl generated f_exprs are Function-typed (Expr(:call, +, ...) as opposed to Expr(:call, :(+), ...))
# MacroTools.unresolve use methodtable lookup, which can't be compiled, thus slow.
function unresolve(expr)
    return MacroTools.prewalk(expr) do sub_expr
        if MacroTools.isexpr(sub_expr, :call) && sub_expr.head == :call && sub_expr.args[1] isa Function
            sub_expr.args[1] = Symbol(sub_expr.args[1])
            # elseif sub_expr isa Distributions.Distribution
            #     sub_expr = Expr(:call, nameof(typeof(sub_expr)), Distributions.params(sub_expr)...)
        end
        return sub_expr
    end
end

function gen_output(compiler_state::CompilerState)
    pregraph = Dict()
    for key in keys(compiler_state.stochasticrules)
        f_expr = gen_f_expr(compiler_state, compiler_state.stochasticrules[key])

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

"""
    gen_chain_transformation(compiler_state, var)

Generate a function of which argument is a MCMCChains chain and return a new chain containing samples 
of variable `var`. `var` has to be a logical variable. 
"""
function gen_chain_transformation(compiler_state, var)
    f_expr = gen_f_expr(compiler_state, var)

    def = MacroTools.splitdef(f_expr)
    new_args = []
    for arg in def[:args]
        # chn[:a] returns a Chain contains all samples of variable a
        push!(new_args, :(getindex(chn, $(QuoteNode(arg)))))
    end

    # e.g., transformation t(a, b) = a + b; to generate a chain of t, requries
    # map(t, chn[:a], chn[:b]) and then wrap the result in a new MCMCChains.Chain
    ret_ex = :(chn -> map(eval($f_expr), :hole))
    splice!(ret_ex.args[2].args[2].args, 3, new_args)

    return ret_ex
end

"""
    process_initializations(inits::Dict, pre_graph, compiler_state::CompilerState)

Generates a dictionary map varaible names to their initial values in the MCMC chain.
"""
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
    init_dict = Dict()
    for key in keys(compiler_state.stochasticrules)
        if haskey(compiler_state.multivariate_variables, key)
            let r = symbolic_eval(compiler_state.multivariate_variables[key], initilizations)
                @assert r isa Array
                rr = similar(r, Any)
                for (i, x) in enumerate(r)
                    let x_unwrapped = Symbolics.unwrap(x)
                        x_unwrapped isa Number ? rr[i] = x_unwrapped : rr[i] = missing
                    end
                end
                if !all(ismissing, rr)
                    init_dict[tosymbol(key)] = rr
                end
            end
        else
            let r = resolve(key, initilizations)
                if !Symbolics.isequal(r, key)
                    init_dict[tosymbol(key)] = r
                end
            end
        end
    end

    return init_dict
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
    @assert target in [:DynamicPPL, :IR, :Graph,] "target must be one of [:DynamicPPL, :IR, :Graph]"

    expr = transform_expr(model_def)

    compiler_state = CompilerState(expr)
    addlogicalrules!(data, compiler_state)
    while true
        # try to unroll as many loops as possible
        while true
            unroll!(expr, compiler_state) ||
                resolveif!(expr, compiler_state) ||
                addlogicalrules!(expr, compiler_state) ||
                addstochasticrules!(expr, compiler_state) ||
                break
        end
        # leave expressions with colon indexing to the last
        # if the following statement is needed to unroll further, then some loop bounds
        # requires colon indexing to resolve. In case like that, if the loop body contains
        # the same array variables used in the loop bounds, we cannot guarantee the correctness. 
        addlogicalrules!(expr, compiler_state, false) || break
    end
    addstochasticrules!(expr, compiler_state, false)

    extract_observations!(compiler_state)

    @assert all(x -> Meta.isexpr(x, (:logical_processed, :stoch_processed)), expr.args) "Some expressions are not processed."

    # `check_expr` will try to unroll the origianl expr again to detect to test 
    # using observed stochastic variables as loop bounds or indexing.
    check_expr(compiler_state)

    target == :IR && return compiler_state

    pre_graph = gen_output(compiler_state)
    g = tograph(pre_graph)
    target == :Graph && return g

    return todppl(g) # target == :DynamicPPL
end
