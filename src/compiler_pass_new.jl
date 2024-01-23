using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using BangBang
using MacroTools
using Missings
using RuntimeGeneratedFunctions
using Setfield
using Graphs, MetaGraphsNext

RuntimeGeneratedFunctions.init(@__MODULE__)
module RHSEval
using JuliaBUGS.BUGSPrimitives
using RuntimeGeneratedFunctions
RuntimeGeneratedFunctions.init(@__MODULE__)
end

function simplify_lhs(::NamedTuple{names,Ts}, lhs::Symbol) where {names,Ts}
    return lhs
end
function simplify_lhs(value_map::NamedTuple{names,Ts}, lhs::Expr) where {names,Ts}
    @assert Meta.isexpr(lhs, :ref)
    @capture(lhs, var_[indices__])
    indices = map(Base.Fix1(simple_arithmetic_eval, value_map), indices)
    indices = map(index -> index isa UnitRange ? index : Int(index), indices)
    return :($(var)[$(indices...)])
end

# simple_arithmetic_eval is used to evaluate the indices of an array or loop bounds
# the return value is either a UnitRange or an Int
function simple_arithmetic_eval(::NamedTuple{names,Ts}, expr::Int) where {names,Ts}
    return expr
end
function simple_arithmetic_eval(
    value_map::NamedTuple{names,Ts}, expr::Symbol
) where {names,Ts}
    if expr ∉ names
        throw(ArgumentError("Don't know the value of $expr."))
    end
    return Int(value_map[expr])
end
function simple_arithmetic_eval(
    value_map::NamedTuple{names,Ts}, expr::Expr
) where {names,Ts}
    @assert Meta.isexpr(expr, (:call, :ref))
    if @capture(expr, f_(args__))
        args = map(Base.Fix1(simple_arithmetic_eval, value_map), args)
        map(args) do arg
            if arg isa UnitRange
                error("Don't know how to do arithmetic between UnitRange and Intger.")
            else
                return Int(arg)
            end
        end
        if f == :+
            return sum(args)
        elseif f == :*
            return prod(args)
        else
            @assert length(args) == 2
            if f == :-
                return args[1] - args[2]
            elseif f == :/
                return Int(args[1] / args[2])
            else # :(:)
                return UnitRange(Int(args[1]), Int(args[2]))
            end
        end
    else # :ref
        @capture(expr, var_[indices__])
        evaluated_indices = map(index -> simple_arithmetic_eval(value_map, index), indices)
        return Int(getindex(value_map[var], evaluated_indices...))
    end
end

function check_if_partially_specified_as_data(
    value_map::NamedTuple{names,Ts}, simplified_lhs
) where {names,Ts}
    if simplified_lhs isa Symbol
        return simplified_lhs in names
    else
        @assert simplified_lhs isa Expr
        @capture(simplified_lhs, var_[indices__])
        if var ∉ names
            return false
        else
            if eltype(value_map[var]) <: Real
                return true
            else
                @assert eltype(value_map[var]) <: Union{Missing,<:Real}
                values = view(value_map[var], indices...)
                # all the values must be all or none missing
                T = typeof(values[1])
                if !all(Base.Fix2(isa, T), values)
                    error(
                        "$(simplified_lhs) is partially specified at data, thus can't be assigned to.",
                    )
                end
                return T != Missing
            end
        end
    end
end

# loop fission makes performance not obvious to programmers: 
# if we do source to source transformation for logp computation, we can add argument so that loops are not touched in the transformed code
function separate_statements(expr::Expr)
    assignments = filter(!Base.Fix2(Meta.isexpr, :for), expr.args)
    fissioned_loops = loop_fission_helper(expr.args)
    return assignments, fissioned_loops
end

function loop_fission_helper(exprs)
    loops = []
    for sub_expr in exprs
        if MacroTools.@capture(
            sub_expr,
            for loop_var_ in l_:h_
                body__
            end
        )
            for ex in body
                if Meta.isexpr(ex, :for)
                    inner_loops = loop_fission_helper([ex])
                else
                    inner_loops = [ex]
                end
                for inner_l in inner_loops
                    push!(loops, MacroTools.@q(
                        for $loop_var in ($l):($h)
                            $inner_l
                        end
                    ))
                end
            end
        end
    end
    return loops
end

function get_vars_and_funs_in_expr(expr)
    if expr isa Number
        return [], []
    elseif expr isa Symbol
        return [expr], []
    elseif expr isa Expr
        vars = Set{Symbol}()
        funs = Set{Symbol}()
        MacroTools.prewalk(expr) do sub_expr
            if @capture(sub_expr, f_(args__))
                push!(funs, f)
                for arg in args
                    if arg isa Symbol
                        push!(vars, arg)
                    end
                end
            elseif @capture(sub_expr, v_[idxs__])
                push!(vars, v)
                for idx in idxs
                    if idx isa Symbol
                        push!(vars, idx)
                    end
                end
            end
            sub_expr
        end
        return collect(vars), collect(setdiff(funs, (:*, :+, :-, :/, :^, :(:)))) # allow :^
    else
        throw(ArgumentError("Argument type $(typeof(expr)) is not supported."))
    end
end

function check_lhs(expr::Expr)
    @assert Meta.isexpr(expr, :ref)
    MacroTools.prewalk(expr) do sub_expr
        if @capture(sub_expr, f_(args__))
            if f ∉ (:+, :-, :*, :/, :(:))
                throw(ErrorException("Function $f is not supported."))
            end
        elseif @capture(sub_expr, fp_Float64)
            throw(
                ArgumentError("Floating point numbers like $fp are not allowed on the LHS.")
            )
        end
        sub_expr
    end
    return expr
end

# for now, assume module captures the values
function to_function(m::Module, lhs, rhs)
    fun_expr = MacroTools.@q function $(repr(lhs))()
        return $(rhs)
    end
    return @RuntimeGeneratedFunction(m, fun_expr)
end

function to_function(m::Module, lhs, rhs, loop_vars)
    fun_expr = MacroTools.@q function $(repr(lhs))($(loop_vars...))
        return $(rhs)
    end
    return @RuntimeGeneratedFunction(m, fun_expr)
end

# E is either = or ~
mutable struct Statement{E}
    lhs
    rhs
    rhs_vars
    rhs_funs
    rhs_function
end

function Statement(expr::Expr)
    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    rhs_vars, rhs_funs = get_vars_and_funs_in_expr(rhs)

    if lhs isa Symbol
        return Statement{sign}(lhs, rhs, rhs_vars, rhs_funs, to_function(RHSEval, lhs, rhs))
    end

    return Statement{sign}(
        check_lhs(lhs), rhs, rhs_vars, rhs_funs, to_function(RHSEval, lhs, rhs)
    )
end

function Base.show(io::IO, statement::Statement{E}) where {E}
    if E == :(=)
        print(io, "$(statement.lhs) = $(statement.rhs)")
    else
        print(io, "$(statement.lhs) ~ $(statement.rhs)")
    end
end

mutable struct ForStatement{E}
    loop_vars
    rhs_vars
    rhs_funs
    bounds
    lhs
    rhs
    rhs_function
end

function ForStatement(expr::Expr)
    loop_vars = []
    bounds = []
    nested_levels = 0
    while Meta.isexpr(expr, :for) # unpack nested loops
        @capture(
            expr,
            for loop_var_ in l_:h_
                body__
            end
        )
        push!(loop_vars, loop_var)
        push!(bounds, :(($l):($h)))
        expr = body[1]
    end

    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    @assert sign ∈ (:~, :(=))
    @assert Meta.isexpr(lhs, :ref)

    rhs_vars, rhs_funs = get_vars_and_funs_in_expr(rhs)

    return ForStatement{sign}(
        loop_vars,
        setdiff(rhs_vars, loop_vars),
        rhs_funs,
        bounds,
        check_lhs(lhs),
        rhs,
        to_function(RHSEval, lhs, rhs, loop_vars),
    )
end

function Base.show(io::IO, for_statement::ForStatement{E}) where {E}
    if E == :(=)
        print(io, "$(for_statement.lhs) = $(for_statement.rhs)")
    else
        print(io, "$(for_statement.lhs) ~ $(for_statement.rhs)")
    end
end

function evaluate_loop_bounds!(for_statement::ForStatement, data)
    for (i, bound) in enumerate(for_statement.bounds)
        bound = simple_arithmetic_eval(data, bound)
        @assert bound isa UnitRange
        for_statement.bounds[i] = bound
    end
    return for_statement
end

# lhs are usually not deep, storing lenses might be overkill, so just dynamically plug in the values
function plug_in_loopvar(for_statement::ForStatement, ::Val{:lhs}, values)
    @assert length(values) == length(for_statement.loop_vars)
    replace_dict = Dict(collect(zip(for_statement.loop_vars, values)))
    return MacroTools.postwalk(for_statement.lhs) do sub_expr
        if MacroTools.@capture(sub_expr, loopvar_Symbol) # only match symbols
            if haskey(replace_dict, loopvar)
                return replace_dict[loopvar]
            end
        end
        sub_expr
    end
end

struct CompileState
    data
    variables_tracked_in_eval_module
    initializations

    logical_statements::Vector{Statement{:(=)}}
    stochastic_statements::Vector{Statement{:(~)}}
    logical_for_statements::Vector{ForStatement{:(=)}}
    stochastic_for_statements::Vector{ForStatement{:(~)}}

    array_sizes
end

function CompileState(expr, data, initializations)
    assignments, fissioned_loops = separate_statements(expr)

    logical_statements = Statement{:(=)}[]
    stochastic_statements = Statement{:(~)}[]
    logical_for_statements = ForStatement{:(=)}[]
    stochastic_for_statements = ForStatement{:(~)}[]

    for assignment in assignments
        statement = Statement(assignment)
        if is_logical(statement)
            push!(logical_statements, statement)
        else
            push!(stochastic_statements, statement)
        end
    end

    for loop in fissioned_loops
        for_statement = ForStatement(loop)
        if is_logical(for_statement)
            push!(logical_for_statements, evaluate_loop_bounds!(for_statement, data))
        else
            push!(stochastic_for_statements, evaluate_loop_bounds!(for_statement, data))
        end
    end

    for (k, v) in pairs(data)
        Base.eval(RHSEval, :($k = $v))
    end

    return CompileState(
        data,
        Set(keys(data)),
        initializations,
        logical_statements,
        stochastic_statements,
        logical_for_statements,
        stochastic_for_statements,
        Dict(),
    )
end

is_logical(::Union{Statement{T},ForStatement{T}}) where {T} = T == :(=)

function determine_array_sizes!(state::CompileState)
    for (k, v) in pairs(state.data) # size of data arrays are known, initializations is treated after compilation
        if v isa Array
            state.array_sizes[k] = size(v)
        end
    end

    for statement in state.logical_statements
        determine_array_sizes_logical!(state, statement.lhs)
    end
    for for_statement in state.logical_for_statements
        for indices in Iterators.product(for_statement.bounds...)
            determine_array_sizes_logical!(
                state, plug_in_loopvar(for_statement, Val(:lhs), indices)
            )
        end
    end
    for statement in state.stochastic_statements
        determine_array_sizes_stochastic!(state, statement.lhs)
    end
    for for_statement in state.stochastic_for_statements
        for indices in Iterators.product(for_statement.bounds...)
            determine_array_sizes_stochastic!(
                state, plug_in_loopvar(for_statement, Val(:lhs), indices)
            )
        end
    end

    # concretize the colon indexing now we know the sizes
    for collection in (
        state.logical_statements,
        state.stochastic_statements,
        state.logical_for_statements,
        state.stochastic_for_statements,
    )
        for statement in collection
            statement.rhs = MacroTools.postwalk(statement.rhs) do sub_expr
                if MacroTools.@capture(sub_expr, v_[indices__])
                    return :($(v)[$(
                        [
                            idx == :(:) ? :(1:($(state.array_sizes[v][i]))) : idx for
                            (i, idx) in enumerate(indices)
                        ]...
                    )])
                end
                sub_expr
            end
        end
    end
end

function determine_array_sizes_logical!(state::CompileState, lhs)
    simplified_lhs = simplify_lhs(state.data, lhs)
    if check_if_partially_specified_as_data(state.data, simplified_lhs)
        throw(ErrorException("$(lhs) is specified at data, thus can't be assigned to."))
    end
    if simplified_lhs isa Symbol # scalar, no need to determine array sizes
        return nothing
    end
    determine_array_sizes_inner!(state, simplified_lhs)
    return nothing
end

function determine_array_sizes_stochastic!(state::CompileState, lhs)
    simplified_lhs = simplify_lhs(state.data, lhs)
    if lhs isa Symbol
        return nothing
    end
    check_if_partially_specified_as_data(state.data, simplified_lhs)
    determine_array_sizes_inner!(state, simplified_lhs)
    return nothing
end

function determine_array_sizes_inner!(state::CompileState, simplified_lhs::Expr)
    @capture(simplified_lhs, lhs_var_[indices__])
    if haskey(state.data, lhs_var)
        # check if the number of dimensions and sizes are consistent with data
        if length(last.(indices)) != length(state.array_sizes[lhs_var])
            @show length(last.(indices)) length(state.array_sizes[lhs_var])
            throw(
                ErrorException(
                    "$(simplified_lhs)'s number of dimensions doesn't match the data."
                ),
            )
        elseif !all(last.(indices) .<= state.array_sizes[lhs_var])
            throw(ErrorException("$(simplified_lhs)'s indices are out of bounds."))
        end
        return nothing
    end
    state.array_sizes[lhs_var] =
        max.(get!(state.array_sizes, lhs_var, [last(indices[1])]), last.(indices))
    return nothing
end

function check_multiple_assignments(state::CompileState)
    # check repeated assignment to scalar variables across all pairs of statements
    for statement_collection in (state.logical_statements, state.stochastic_statements)
        for (i, statement) in enumerate(statement_collection)
            if !(statement.lhs isa Symbol)
                continue
            end
            for j in (i + 1):length(statement_collection)
                if !(statement_collection[j].lhs isa Symbol)
                    continue
                end
                if statement.lhs == statement_collection[j].lhs
                    throw(
                        ErrorException(
                            "$statement and $(statement_collection[j]) are both assigning to $(statement.lhs).",
                        ),
                    )
                end
            end
        end
    end

    for statement_collection in (
        vcat(state.logical_statements, state.logical_for_statements),
        vcat(state.stochastic_statements, state.stochastic_for_statements),
    )
        definition_map = Dict()
        for (k, v) in state.array_sizes
            if k ∉ keys(state.data)
                definition_map[k] = falses(v...)
            end
        end

        for statement in statement_collection
            if statement.lhs isa Symbol
                continue
            end

            if statement.lhs.args[1] ∉ keys(definition_map)
                continue
            end

            if statement isa Statement
                check_multiple_assignments_inner!(state, statement.lhs, definition_map)
            else
                for indices in Iterators.product(statement.bounds...)
                    check_multiple_assignments_inner!(
                        state,
                        plug_in_loopvar(statement, Val(:lhs), indices),
                        definition_map,
                    )
                end
            end
        end
    end

    # cases where a logical statement and a stochastic statement assign to the same array location is not checked
    # because it might be a valid case when the variable under inspection is a transformed variable
    # this check will be done after `compute_transformed!`
end

function check_multiple_assignments_inner(state, lhs, definition_map)
    simplified_lhs = simplify_lhs(state.data, lhs)
    @capture(simplified_lhs, lhs_var_[indices__])
    if_defined = definition_map[lhs_var][indices...]
    if any(if_defined .== true)
        @show indices if_defined
        all_indices = collect(Iterators.product(indices...))
        repeated_def_indices = all_indices[findall(if_defined)]
        throw(
            ErrorException(
                "Multiple assignments to variable $(lhs_var) at indices $(join(repeated_def_indices, ", ")) are not allowed.",
            ),
        )
    end
    return setindex!!(definition_map[lhs_var], trues(length.(indices)...), indices...)
end

FUNCTION_TO_ATTEMPT_EVAL = copy(JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS) # can also add user defined functions

function compute_transformed!(state::CompileState)
    new_value_added = true
    evaluated_logical_statements = []
    evaluated_logical_for_statements = []
    evaluated_logical_for_statement_indices = Dict{Int,BitArray}()
    while new_value_added
        new_value_added = false

        for (i, statement) in enumerate(state.logical_statements)
            if i in evaluated_logical_statements
                continue
            end

            if !all(Base.Fix2(∈, FUNCTION_TO_ATTEMPT_EVAL), statement.rhs_funs)
                push!(evaluated_logical_statements, i)
                continue
            end

            if !all(Base.Fix2(∈, state.variables_tracked_in_eval_module), statement.rhs_vars)
                continue
            end

            if statement.lhs isa Symbol
                rhs = statement.rhs_function()
                if rhs isa Missing
                    continue
                end
                Base.eval(RHSEval, :($(statement.lhs) = $(rhs)))
                push!(evaluated_logical_statements, i)
                new_value_added = true
            else # Expr
                new_value_added = compute_transformed_inner!(state, statement)
                if new_value_added
                    push!(evaluated_logical_statements, i)
                end
            end
        end

        for (i, for_statement) in enumerate(state.logical_for_statements)
            if i in evaluated_logical_for_statements
                continue
            end

            if i in keys(evaluated_logical_for_statement_indices)
                if all(evaluated_logical_for_statement_indices[i])
                    push!(evaluated_logical_for_statements, i)
                    continue
                end
            end

            if !all(Base.Fix2(∈, FUNCTION_TO_ATTEMPT_EVAL), for_statement.rhs_funs)
                push!(evaluated_logical_for_statements, i)
                continue
            end

            if !all(Base.Fix2(∈, state.variables_tracked_in_eval_module), for_statement.rhs_vars)
                continue
            end

            evaluated_indices_array = get!(
                evaluated_logical_for_statement_indices,
                i,
                falses(state.array_sizes[for_statement.lhs.args[1]]...),
            )
            for indices in Iterators.product(for_statement.bounds...)
                new_value_added_local = compute_transformed_inner!(
                    state, for_statement, indices
                )
                if new_value_added_local
                    evaluated_indices_array[indices...] = true
                end
                new_value_added = new_value_added_local || new_value_added
            end
        end
    end
    # check if a logical statement and a stochastic statement assign to the same array location
    # TODO
end

function compute_transformed_inner!(state, statement)
    simplified_lhs = simplify_lhs(state.data, statement.lhs)

    # TODO: check if we already computed the value; need to take care of the case where the value is missing and return false

    value = statement.rhs_function()
    return store_values!(state, simplified_lhs, value)
end

function compute_transformed_inner!(state, for_statement, indices)
    simplified_lhs = simplify_lhs(
        state.data, plug_in_loopvar(for_statement, Val(:lhs), indices)
    )

    # TODO: check if we already computed the value; need to take care of the case where the value is missing and return false
    value = for_statement.rhs_function(indices...)
    return store_values!(state, simplified_lhs, value)
end

function store_values!(state, simplified_lhs, value)
    if value isa Expr
        return false
    elseif value isa Real || eltype(value) <: Real || all(Base.Fix2(isa, Real), value)
        @capture(simplified_lhs, lhs_var_[indices__])
        if lhs_var ∉ state.variables_tracked_in_eval_module
            push!(state.variables_tracked_in_eval_module, lhs_var)
            Base.eval(
                RHSEval, :($lhs_var = $(fill(missing, state.array_sizes[lhs_var]...)))
            )
        end

        # special case: data array contains missing values, then we need to make a copy before mutating
        if lhs_var ∈ keys(state.data)
            if getfield(RHSEval, lhs_var) === state.data[lhs_var] # haven't been copied
                Base.eval(RHSEval, :($lhs_var = $(copy(state.data[lhs_var]))))
            end
        end

        setproperty!(RHSEval, lhs_var, setindex!!(getfield(RHSEval, lhs_var), value, indices...))
        return true
    else # catch other possible types by evaluating other functions
        return false
    end
end

##
using JuliaBUGS: program!, CollectVariables, ConstantPropagation, PostChecking

##
m = :leuk
model_def = JuliaBUGS.BUGSExamples.leuk.model_def
data = JuliaBUGS.BUGSExamples.leuk.data
inits = JuliaBUGS.BUGSExamples.leuk.inits[1]

##
scalars, array_sizes = program!(CollectVariables(), model_def, data)
has_new_val, transformed = program!(
    ConstantPropagation(scalars, array_sizes), model_def, data
)
while has_new_val
    has_new_val, transformed = program!(
        ConstantPropagation(false, transformed), model_def, data
    )
end
array_bitmap, transformed = program!(PostChecking(data, transformed), model_def, data)

##
state = CompileState(model_def, data, inits)
determine_array_sizes!(state)
compute_transformed!(state)

##

model_def = @bugs begin
    x[1:3] = y[1:3]
    x[5] = x[4]
    z[1:2] = x[5:6]
end

state = CompileState(
    model_def, (y=[1, 2, 3], x=[missing, missing, missing, 1, missing, 2]), NamedTuple()
)

determine_array_sizes!(state)
compute_transformed!(state)

@assert state.merged_data_and_transformed[:x] == [1, 2, 3, 1, 1, 2]

model_def = @bugs begin
    for i in 1:3
        x[i] = y[i]
    end

    for i in 1:10
        x[i] ~ Normal(0, 1)
    end

    z = sum(x[:])
end

state = CompileState(model_def, (y=[1, 2, 3],), NamedTuple())
state = CompileState(model_def, (;), NamedTuple())

model_def = @bugs begin
    x[1:3] = y[1:3]
    x[1] = 2
end

model_def = @bugs begin
    for i in 2:3
        x[(i - 1):(i + 1)] = y[1:3]
    end
end

state = CompileState(model_def, (y=[1, 2, 3],), NamedTuple())

determine_array_sizes!(state)
check_multiple_assignments(state)

#################################### not used
function numeric_evaluate(env, expr; m::Module=Main, allowed_functions=[])
    if expr isa Float64 # for ease of indexing
        return isinteger(expr) ? Int(expr) : expr
    elseif expr isa Union{Int,UnitRange}
        return expr
    elseif expr isa Symbol
        if haskey(env, expr)
            return env[expr]
        elseif Base.isidentifier(expr)
            return expr
        else
            if expr == :(:)
                throw(
                    ArgumentError(
                        "Colon indexing is not supported with `evaluate`, all colon indexing should be made concrete.",
                    ),
                )
            else
                throw(ArgumentError("Unknown symbol $expr."))
            end
        end
    elseif expr isa Expr
        if Meta.isexpr(expr, :ref)
            @capture(expr, var_[indices__])

            evaluated_indices = [
                evaluate(env, index; m=m, allowed_functions=allowed_functions) for
                index in indices
            ]

            for (i, index) in enumerate(evaluated_indices)
                if !(index isa Int) && !(index isa UnitRange) && !(index isa Expr)
                    throw(ArgumentError("Can't index with $(indices[i])."))
                end
            end

            if var ∉ keys(env)
                return :($(var)[$(evaluated_indices...)])
            end

            if any(Base.Fix2(isa, Expr), evaluated_indices) # some indices are not evaluated
                return Expr(:ref, var, evaluated_indices...)
            end

            value = if all(Base.Fix2(isa, Int), evaluated_indices)
                env[var][evaluated_indices...] # if all indices are Int, then the value is a scalar, just return the value
            else
                view(env[var], evaluated_indices...) # otherwise, return a view of the array
            end

            if value isa Real
                return value
            elseif eltype(value) <: Real
                return value
            elseif all(Base.Fix2(isa, Real), value) # eltype is Union{Missing,Float64}, but all values are non-missing
                return value
            else
                return expr
            end
        elseif Meta.isexpr(expr, :call)
            @capture(expr, f_(args__))
            evaluated_args = map(
                x -> evaluate(env, x; m=m, allowed_functions=allowed_functions), args
            )

            if !all(Base.Fix2(isa, Union{<:Real,UnitRange}), evaluated_args)
                returned_args = [
                    evaluated_arg isa Union{<:Real,UnitRange} ? evaluated_arg : arg for
                    (arg, evaluated_arg) in zip(args, evaluated_args)
                ]

                if f == :(+) # simplify addition
                    number_terms = filter(Base.Fix2(isa, Number), returned_args)
                    expr_terms = filter(!Base.Fix2(isa, Number), returned_args)
                    return Expr(:call, :+, sum(number_terms), expr_terms...)
                end

                return Expr(:call, f, returned_args...)
            end

            # then all args are evaluated
            if f == :(+)
                return sum(evaluated_args)
            elseif f == :(*)
                return prod(evaluated_args)
            elseif f in (:-, :/, :(:))
                @assert length(evaluated_args) == 2
                if f == :-
                    return evaluated_args[1] - evaluated_args[2]
                elseif f == :/
                    return evaluated_args[1] / evaluated_args[2]
                else
                    return UnitRange(Int(evaluated_args[1]), Int(evaluated_args[2]))
                end
            elseif f in allowed_functions
                return (getfield(m, f))(evaluated_args...)
            else
                throw(ErrorException("Function $f is not supported."))
            end
        else
            error("Expression type $(expr.args[1]) is not supported.")
        end
    else
        error("Argument type $(typeof(expr)) is not supported.")
    end
end

# a variable is uniquely identified by expression id and loop var bindings
function get_loop_var_lenses(expr, loop_vars)
    lenses_map = Dict()
    for loop_var in loop_vars
        lenses = get_lens(expr, loop_var, Setfield.IdentityLens())
        lenses_map[loop_var] = lenses
    end
    return lenses_map
end

function get_lens(expr, target_expr, parent_lens)
    if expr isa Union{Symbol,Number} # didn't find
        return []
    end

    lenses = [] # possible multiple occurrences
    if expr.head == target_expr
        push!(lenses, parent_lens ∘ (@lens _.head))
    end
    for (i, arg) in enumerate(expr.args)
        if arg == target_expr
            push!(lenses, parent_lens ∘ (@lens _.args[i]))
        else
            child_lenses = get_lens(arg, target_expr, parent_lens ∘ (@lens _.args[i]))
            for lens in child_lenses
                push!(lenses, lens)
            end
        end
    end
    return lenses
end

function plug_in_loopvar(for_statement::ForStatement, ::Val{:rhs}, values)
    @assert length(values) == length(for_statement.loop_vars)
    expr = for_statement.rhs
    for (loop_var, value) in zip(for_statement.loop_vars, values)
        for lens in for_statement.rhs_loop_vars_lens[loop_var]
            expr = set(expr, lens, value)
        end
    end
    return expr
end
