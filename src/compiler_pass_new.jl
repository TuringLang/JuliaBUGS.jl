using JuliaBUGS, MacroTools
using JuliaBUGS.BUGSPrimitives
using BangBang, Setfield
using DynamicPPL
using MetaGraphsNext, Graphs

function evaluate(
    env,
    expr;
    module_name=Main,
    return_missing=false,
    arithmetic_functions=(:*, :+, :-, :/, :^),
    allowed_functions=[],
    all_allowed_functions=union(arithmetic_functions, allowed_functions),
)
    if expr isa Float64 # for ease of indexing
        return isinteger(expr) ? Int(expr) : expr
    elseif expr isa Union{Int,UnitRange}
        return expr
    elseif expr isa Symbol
        if haskey(env, expr)
            return env[expr]
        else
            return expr
        end
    elseif expr isa Expr
        expr = copy(expr)
        if Meta.isexpr(expr, :ref)
            @assert all(Base.Fix1(!==, :(:)), expr.args[2:end]) # no colon indexing
            expr = Expr(
                :ref, expr.args[1], map(Base.Fix1(evaluate, env), expr.args[2:end])...
            )
            if !haskey(env, expr.args[1]) || any(Base.Fix2(isa, Expr), expr.args[2:end])
                return expr
            end
            @assert all(Base.Fix2(isa, Union{Int,UnitRange{Int}}), expr.args[2:end])
            value = getindex(env[expr.args[1]], expr.args[2:end]...) # TODO: maybe view?
            if return_missing || !ismissing(value) && !any(ismissing, value)
                return value
            else
                return expr
            end
        elseif Meta.isexpr(expr, :call)
            expr = Expr(
                :call, expr.args[1], map(Base.Fix1(evaluate, env), expr.args[2:end])...
            )
            if all(Base.Fix2(isa, Union{Real,Array{Real}}), expr.args[2:end])
                if expr.args[1] == :(:)
                    return (:)(expr.args[2:end]...)
                elseif expr.args[1] ∈ all_allowed_functions
                    evaluate_result = (getfield(module_name, expr.args[1]))(
                        expr.args[2:end]...
                    )
                    if return_missing ||
                        !ismissing(evaluate_result) && !any(ismissing, evaluate_result)
                        return evaluate_result
                    else
                        return expr
                    end
                end
            else
                if expr.args[1] == :(+)
                    number_terms = filter(Base.Fix2(isa, Number), expr.args[2:end])
                    expr_terms = filter(!Base.Fix2(isa, Number), expr.args[2:end])
                    return Expr(:call, :+, sum(number_terms), expr_terms...)
                end
                return expr
            end
        else
            error("Expression type $(expr.args[1]) is not supported.")
        end
    else
        error("Argument type $(typeof(expr)) is not supported.")
    end
end

# loop fission makes performance not obvious to programmers: 
# if we do source to source transformation for logp computation, we can add argument so that loops are not touched in the transformed code
function separate_statements(@nospecialize(expr))
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
        return collect(vars), collect(setdiff(funs, (:*, :+, :-, :/, :^, :(:))))
    else
        error("Argument type $(typeof(expr)) is not supported.")
    end
end

# E is either = or ~
mutable struct Statement{E}
    lhs
    rhs
    rhs_vars
    rhs_funs
end

function Statement(@nospecialize(expr))
    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    @assert sign ∈ (:~, :(=))
    rhs_vars, rhs_funs = get_vars_and_funs_in_expr(rhs)
    return Statement{sign}(lhs, rhs, rhs_vars, rhs_funs)
end

mutable struct ForStatement{E}
    nested_levels::Int
    loop_vars
    rhs_loop_vars_lens
    rhs_vars
    rhs_funs
    bounds
    lhs
    rhs
end

function ForStatement(@nospecialize(expr))
    nested_levels = 0
    loop_vars = []
    bounds = []
    while Meta.isexpr(expr, :for) # unpack nested loops
        @capture(
            expr,
            for loop_var_ in l_:h_
                body__
            end
        )
        push!(loop_vars, loop_var)
        push!(bounds, :(($l):($h)))
        nested_levels += 1
        expr = body[1]
    end

    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    @assert sign ∈ (:~, :(=))
    @assert Meta.isexpr(lhs, :ref)
    rhs_loop_vars_lens = get_loop_var_lenses(rhs, loop_vars)
    rhs_vars, rhs_funs = get_vars_and_funs_in_expr(rhs)
    return ForStatement{sign}(
        nested_levels,
        loop_vars,
        rhs_loop_vars_lens,
        setdiff(rhs_vars, loop_vars),
        rhs_funs,
        bounds,
        lhs,
        rhs,
    )
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

function evaluate_loop_bounds!(for_statement::ForStatement, data)
    for (i, bound) in enumerate(for_statement.bounds)
        bound = evaluate(data, bound)
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

# TODO: can just evaluate the rhs to a function at the creation of CompileState
struct CompileState
    data
    merged_data_and_transformed
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

    return CompileState(
        data,
        data == NamedTuple() ? Dict() : Dict(pairs(data)), # merged_data_and_transformed is the same as data at the beginning
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
    # only look at the LHS
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

    for for_statement in vcat(state.logical_for_statements, state.stochastic_for_statements)
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
    evaluated_lhs = evaluate(state.data, lhs; return_missing=true)
    if ismissing(evaluated_lhs)
        if lhs isa Symbol
            error("The data shouldn't contain scalar missing values.")
        else
            determine_array_sizes_inner!(
                state,
                Expr(
                    :ref,
                    lhs.args[1],
                    map(Base.Fix1(evaluate, state.data), lhs.args[2:end])...,
                ),
            )
        end
    elseif evaluated_lhs isa Symbol
        return nothing # no need to determine array sizes for scalars
    elseif evaluated_lhs isa Array
        if eltype(evaluated_lhs) <: Real || all(!ismissing, evaluated_lhs) # eltype can be Union{Missing,Float64} even if all values are non-missing
            error("$(lhs) is specified at data, thus can't be assigned to.")
        elseif all(ismissing, evaluated_lhs) # this is fine, but we need to get the Expr of the LHS
            determine_array_sizes_inner!(
                state,
                Expr(
                    :ref,
                    lhs.args[1],
                    map(Base.Fix1(evaluate, state.data), lhs.args[2:end])...,
                ),
            )
        else # some missing values, the others are data
            error("$(lhs) is specified at data, thus can't be assigned to.")
        end
    elseif evaluated_lhs isa Expr
        determine_array_sizes_inner!(state, evaluated_lhs)
    else
        error("Don't know how to handle $(lhs).")
    end
end

function determine_array_sizes_stochastic!(state::CompileState, lhs)
    if lhs isa Symbol # if it's a scalar
        return nothing
    end
    evaluated_lhs = evaluate(state.data, lhs; return_missing=true)
    if ismissing(evaluated_lhs) || evaluated_lhs isa Real # random variables: unobserved or observed
        return nothing # because `evaluate` didn't error, it's fine
    elseif evaluated_lhs isa Array
        if eltype(evaluated_lhs) <: Real ||
            all(!ismissing, evaluated_lhs) ||
            all(ismissing, evaluated_lhs)
            return nothing # because `evaluate` didn't error, it's fine
        else # mixed missing and non-missing
            error("Unobserved values can't be mixed with observed values at $(lhs).")
        end
    elseif evaluated_lhs isa Expr
        determine_array_sizes_inner(state, evaluated_lhs)
    else
        error("Don't know how to handle $(lhs).")
    end
end

function determine_array_sizes_inner!(state::CompileState, lhs::Expr)
    if @capture(lhs, lhs_var_[indices__])
        @assert all(Base.Fix2(isa, Union{Int,UnitRange{Int}}), indices) "Some indices can't be decided at compile time."
        if haskey(state.data, lhs_var)
            @assert length(last.(indices)) == ndims(state.data[lhs_var]) &&
                all(last.(indices) .<= size(state.data[lhs_var]))
            return nothing
        end
        if haskey(state.array_sizes, lhs_var)
            state.array_sizes[lhs_var] = max.(state.array_sizes[lhs_var], last.(indices)) # check ndims implicitly
        else
            state.array_sizes[lhs_var] = [last.(indices)...]
        end
    else
        error("LHS $lhs should be a :ref expression.")
    end
end

FUNCTION_TO_ATTEMPT_EVAL = copy(JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS) # can also add user defined functions

function compute_transformed!(state::CompileState)
    new_value_added = true
    while new_value_added
        new_value_added = false

        for statement in state.logical_statements
            if can_skip(state.merged_data_and_transformed, statement)
                continue
            end
            # because `determine_array_sizes!` has done the checks, we can assume that `evaluate(data, statement.lhs)` returns a Symbol or Expr
            lhs = evaluate(state.data, statement.lhs)

            if lhs isa Symbol
                if evaluate(state.merged_data_and_transformed, lhs) isa Real
                    continue
                end
                rhs = evaluate(state.merged_data_and_transformed, statement.rhs)
                if rhs isa Real
                    state.merged_data_and_transformed[lhs] = rhs
                    new_value_added = true
                end
            elseif lhs isa Expr
                new_value_added = compute_transformed_inner!(state, lhs, statement.rhs)
            else
                error("Don't know how to handle $(lhs).")
            end
        end

        for for_statement in state.logical_for_statements
            if can_skip(state.merged_data_and_transformed, for_statement)
                continue
            end

            for indices in Iterators.product(for_statement.bounds...)
                new_value_added =
                    compute_transformed_inner!(
                        state,
                        plug_in_loopvar(for_statement, Val(:lhs), indices),
                        plug_in_loopvar(for_statement, Val(:rhs), indices),
                    ) || new_value_added
            end
        end
    end
end

function can_skip(env, stmt::Union{Statement{:(=)},ForStatement{:(=)}})
    return !all(Base.Fix2(∈, FUNCTION_TO_ATTEMPT_EVAL), stmt.rhs_funs) ||
           !all(Base.Fix2(∈, keys(env)), stmt.rhs_vars)
end

function compute_transformed_inner!(state, lhs::Expr, rhs)
    evaluated_lhs = evaluate(state.merged_data_and_transformed, lhs) # this time evaluate lhs in `merged_data_and_transformed` 
    # instead of data to check if it's already evaluated

    if evaluated_lhs isa Real
        return false
    elseif evaluated_lhs isa Array
        if eltype(evaluated_lhs) <: Real || all(Base.Fix2(isa, Real), evaluated_lhs)
            return false
        end
    end

    @assert evaluated_lhs isa Expr
    # then the statement has not been evaluated
    value = evaluate(
        state.merged_data_and_transformed, rhs; allowed_functions=FUNCTION_TO_ATTEMPT_EVAL
    )
    if value isa Union{Real,Array{<:Real}} || all(Base.Fix2(isa, Real), value)
        if @capture(lhs, lhs_var_[indices__])
            if !haskey(state.merged_data_and_transformed, lhs_var)
                state.merged_data_and_transformed[lhs_var] = Array{Union{Missing,Float64}}(
                    missing, state.array_sizes[lhs_var]...
                )
                # special case: data array contains missing values, then we need to make a copy before mutating
            elseif lhs_var ∈ keys(state.data) &&
                state.merged_data_and_transformed[lhs_var] === state.data[lhs_var] # haven't been copied
                state.merged_data_and_transformed[lhs_var] = copy(state.data[lhs_var])
            end
            setindex!!(state.merged_data_and_transformed[lhs_var], value, indices...)
            return true
        else
            error("LHS $lhs should be a :ref expression.")
        end
    else
        return false
    end
end

# function check_multiple_assignments(state::CompileState)
#     all_statements = vcat(
#         state.logical_statements,
#         state.logical_for_statements,
#         state.stochastic_statements,
#         state.stochastic_for_statements,
#     ) # logical before stochastic
#     env = state.data

#     d = []
#     for statement in state.logical_statements
#         if statement.lhs isa Symbol
#             push!(d, statement.lhs)
#         end
#     end
#     d2 = []
#     for statement in state.stochastic_statements
#         if statement.lhs isa Symbol
#             push!(d2, statement.lhs)
#         end
#     end
#     i = intersect(d, d2)
#     if any(evaluate(state.merged_data_and_transformed, stmt.lhs) isa Symbol for stmt in all_statements)
#         error("The same variable can't be assigned to both deterministically and stochastically.")
#     end

#     lhs_vars = [statement.lhs isa Symbol ? statement.lhs : statement.lhs.args[1] for statement in all_statements]
#     binned_statement_id_by_lhs_var = Dict()
#     for (i, lhs_var) in enumerate(lhs_vars)
#         push!(get!(binned_statement_id_by_lhs_var, lhs_var, []), i)
#     end

#     for (lhs_var, statement_ids) in binned_statement_id_by_lhs_var
#         bit_array = falses(state.array_sizes[lhs_var]...)
#         for statement_id in statement_ids
#             stmt = all_statements[statement_id] # stmt can be either Statement or ForStatement
#             if stmt
#             indices_covered_by_statement = if all_statements[statement_id] isa Statement
#                 statement = all_statements[statement_id]
#                 [find_variables_on_lhs(statement.lhs, data).indices] # wrap in a vector for consistency
#             else # ForStatement
#                 for_statement = all_statements[statement_id]
#                 covered_indices = []
#                 for indices in Iterators.product(for_statement.bounds...)
#                     lhs = evaluate(env, plug_in_loopvar(for_statement, Val(:lhs), indices))

#                     push!(
#                         covered_indices,
#                         find_variables_on_lhs(for_statement.lhs, local_env).indices,
#                     )
#                 end
#                 covered_indices
#             end
#             for indices in indices_covered_by_statement # indices_covered_by_statement is a vector of vectors
#                 if any(Base.Fix2(isa, AbstractRange), indices)
#                     for idx in Iterators.product(indices...)
#                         if bit_array[idx...]
#                             # special case: transformed variable as observation
#                             if haskey(state.transformed, lhs_var) &&
#                                 !ismissing(state.transformed[lhs_var][idx...]) &&
#                                 !is_logical(all_statements[statement_ids[statement_id]])
#                                 continue
#                             end
#                             error(
#                                 "Multiple assignments to $lhs_var at the same position is not allowed.",
#                             )
#                         end
#                         bit_array[idx...] = true
#                     end
#                 else # no UnitRange involved
#                     idx = indices
#                     if bit_array[idx...]
#                         # special case: transformed variable as observation
#                         if haskey(state.transformed, lhs_var) &&
#                             !ismissing(state.transformed[lhs_var][idx...]) &&
#                             !is_logical(all_statements[statement_ids[statement_id]])
#                             continue
#                         end
#                         error(
#                             "Multiple assignments to $lhs_var at the same position is not allowed.",
#                         )
#                     end
#                     bit_array[idx...] = true
#                 end
#             end
#         end
#     end
# end

# struct NodeInfo end

# function build_graph(state::CompileState)
#     return g = MetaGraph(DiGraph(), VarName, NodeInfo)
# end

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
