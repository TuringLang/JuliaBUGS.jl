using JuliaBUGS, MacroTools
using JuliaBUGS: Var, Scalar, ArrayElement, ArrayVar, to_varname
using JuliaBUGS: check_idxs, find_variables_on_lhs, is_resolved, should_skip_eval
using JuliaBUGS.BUGSPrimitives
using BangBang
using DynamicPPL
using MacroTools
using MetaGraphsNext, Graphs
using Setfield

function evaluate(
    env,
    expr;
    module_name=Main,
    arithmetic_functions=(:*, :+, :-, :/, :^),
    allowed_functions=[],
    all_allowed_functions=union(
        arithmetic_functions, JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS
    ),
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
            @assert all(Base.Fix1(!==, :(:)), expr.args[2:end])
            expr = Expr(
                :ref, expr.args[1], map(Base.Fix1(evaluate, env), expr.args[2:end])...
            )
            if !haskey(env, expr.args[1]) || any(Base.Fix2(isa, Expr), expr.args[2:end])
                return expr
            end
            @assert all(Base.Fix2(isa, Union{Int,UnitRange{Int}}), expr.args[2:end])
            value = getindex(env[expr.args[1]], expr.args[2:end]...)
            if ismissing(value) || any(ismissing, value)
                return expr
            else
                return value
            end
        elseif Meta.isexpr(expr, :call)
            expr = Expr(
                :call, expr.args[1], map(Base.Fix1(evaluate, env), expr.args[2:end])...
            )
            if all(Base.Fix2(isa, Union{Real,Array{Real}}), expr.args[2:end])
                if expr.args[1] == :(:)
                    return (:)(expr.args[2:end]...)
                elseif expr.args[1] ∈ all_allowed_functions
                    return (getfield(module_name, expr.args[1]))(expr.args[2:end]...)
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

    scalars
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
        [],
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

    env = state.data

    function determine_array_sizes_inner(lhs)
        @capture(lhs, lhs_var_[indices__])
        @assert all(Base.Fix2(isa, Union{Int,UnitRange{Int}}), indices)
        if haskey(env, lhs_var)
            @assert length(last.(indices)) == ndims(env[lhs_var]) &&
                all(last.(indices) .<= size(env[lhs_var]))
            return nothing
        end
        if haskey(state.array_sizes, lhs_var)
            state.array_sizes[lhs_var] = max.(state.array_sizes[lhs_var], last.(indices)) # check ndims implicitly
        else
            state.array_sizes[lhs_var] = [last.(indices)...]
        end
    end

    for statement in vcat(state.logical_statements, state.stochastic_statements)
        lhs = evaluate(env, statement.lhs)
        if is_logical(statement) && lhs isa Union{Real,Array{<:Real}}
            error("$lhs is specified at data, thus can't be assigned to.")
        end
        if lhs isa Symbol
            push!(state.scalars, lhs)
        else
            determine_array_sizes_inner(lhs)
        end
    end

    for for_statement in vcat(state.logical_for_statements, state.stochastic_for_statements)
        for indices in Iterators.product(for_statement.bounds...)
            lhs = evaluate(env, plug_in_loopvar(for_statement, Val(:lhs), indices))
            if is_logical(for_statement) && lhs isa Union{Real,Array{<:Real}}
                error("$lhs is specified at data, thus can't be assigned to.")
            end
            if lhs isa Scalar
                error("Scalar definition inside a loop is not supported.")
            else
                determine_array_sizes_inner(lhs)
            end
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

FUNCTION_TO_ATTEMPT_EVAL = copy(JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS) # can also add user defined functions

function is_union_of_missing(T)
    return T <: Union{Missing}
end

# TODO: test multi-dim function and missing values in data
function compute_transformed!(state::CompileState)
    new_value_added = true
    env = state.merged_data_and_transformed
    while new_value_added
        new_value_added = false

        for statement in state.logical_statements
            if !all(Base.Fix2(∈, FUNCTION_TO_ATTEMPT_EVAL), statement.rhs_funs) ||
                !all(Base.Fix2(∈, keys(env)), statement.rhs_vars)
                continue
            end

            lhs = evaluate(data, statement.lhs)

            if lhs isa Symbol
                if evaluate(env, lhs) isa Real
                    continue
                end
                rhs = evaluate(env, statement.rhs)
                if rhs isa Real
                    state.merged_data_and_transformed[lhs] = rhs
                    new_value_added = true
                end
            else
                if evaluate(env, lhs) isa Union{Real,Array{<:Real}}
                    continue
                end
                value = evaluate(
                    env, statement.rhs; allowed_functions=FUNCTION_TO_ATTEMPT_EVAL
                )
                if value isa Union{Real,Array{<:Real}}
                    @capture(lhs, lhs_var_[indices__])
                    if !haskey(env, lhs_var)
                        state.merged_data_and_transformed[lhs_var] = Array{
                            Union{Missing,Float64}
                        }(
                            missing, state.array_sizes[lhs_var]...
                        )
                    elseif haskey(env, lhs_var) &&
                        lhs_var ∉ setdiff(
                        keys(state.merged_data_and_transformed), keys(state.data)
                    )
                        state.merged_data_and_transformed[lhs_var] = copy(env[lhs_var])
                    end
                    setindex!!(
                        state.merged_data_and_transformed[lhs_var], value, indices...
                    )
                    new_value_added = true
                end
            end
        end

        for for_statement in state.logical_for_statements
            if !all(Base.Fix2(∈, FUNCTION_TO_ATTEMPT_EVAL), for_statement.rhs_funs) ||
                !all(Base.Fix2(∈, keys(env)), for_statement.rhs_vars)
                continue
            end

            for indices in Iterators.product(for_statement.bounds...)
                lhs = evaluate(data, plug_in_loopvar(for_statement, Val(:lhs), indices))
                if evaluate(env, lhs) isa Union{Real,Array{<:Real}}
                    continue
                end
                value = evaluate(
                    env,
                    plug_in_loopvar(for_statement, Val(:rhs), indices);
                    allowed_functions=FUNCTION_TO_ATTEMPT_EVAL,
                ) # evaluate the rhs
                if value isa Union{Real,Array{<:Real}}
                    @capture(lhs, lhs_var_[indices__])
                    if !haskey(env, lhs_var)
                        state.merged_data_and_transformed[lhs_var] = Array{
                            Union{Missing,Float64}
                        }(
                            missing, state.array_sizes[lhs_var]...
                        )
                    elseif haskey(env, lhs_var) &&
                        lhs_var ∉ setdiff(
                        keys(state.merged_data_and_transformed), keys(state.data)
                    )
                        state.merged_data_and_transformed[lhs_var] = copy(env[lhs_var])
                    end
                    setindex!!(
                        state.merged_data_and_transformed[lhs_var], value, indices...
                    )
                    new_value_added = true
                end
            end
        end
    end

    for (k, v) in pairs(state.merged_data_and_transformed)
        if eltype(v) <: Union{Missing,<:Real}
            state.merged_data_and_transformed[k] = identity.(v)
        end
    end
end

function check_multiple_assignments(state::CompileState)
    all_statements = vcat(
        state.logical_statements,
        state.logical_for_statements,
        state.stochastic_statements,
        state.stochastic_for_statements,
    ) # logical before stochastic
    data = state.data

    lhs_vars = [
        statement isa Statement ? statement.lhs : statement.lhs.args[1] for
        statement in all_statements
    ]
    # cluster statements by lhs
    clusters = Dict()
    for (i, lhs_var) in enumerate(lhs_vars)
        if haskey(clusters, lhs_var)
            push!(clusters[lhs_var], i)
        else
            clusters[lhs_var] = [i]
        end
    end

    for (lhs_var, statement_ids) in pairs(clusters)
        bit_array = falses(state.array_sizes[lhs_var]...)

        for statement_id in statement_ids
            statement = all_statements[statement_id]
            indices_covered_by_statement = if all_statements[statement_id] isa Statement
                statement = all_statements[statement_id]
                [find_variables_on_lhs(statement.lhs, data).indices] # wrap in a vector for consistency
            else # ForStatement
                for_statement = all_statements[statement_id]
                covered_indices = []
                for indices in Iterators.product(for_statement.bounds...)
                    local_env = merge(copy(Dict(pairs(data))), state.transformed)
                    for (loop_var, bounds) in zip(for_statement.loop_vars, indices)
                        local_env[loop_var] = bounds
                    end

                    push!(
                        covered_indices,
                        find_variables_on_lhs(for_statement.lhs, local_env).indices,
                    )
                end
                covered_indices
            end
            for indices in indices_covered_by_statement # indices_covered_by_statement is a vector of vectors
                if any(Base.Fix2(isa, AbstractRange), indices)
                    for idx in Iterators.product(indices...)
                        if bit_array[idx...]
                            # special case: transformed variable as observation
                            if haskey(state.transformed, lhs_var) &&
                                !ismissing(state.transformed[lhs_var][idx...]) &&
                                !is_logical(all_statements[statement_ids[statement_id]])
                                continue
                            end
                            error(
                                "Multiple assignments to $lhs_var at the same position is not allowed.",
                            )
                        end
                        bit_array[idx...] = true
                    end
                else # no UnitRange involved
                    idx = indices
                    if bit_array[idx...]
                        # special case: transformed variable as observation
                        if haskey(state.transformed, lhs_var) &&
                            !ismissing(state.transformed[lhs_var][idx...]) &&
                            !is_logical(all_statements[statement_ids[statement_id]])
                            continue
                        end
                        error(
                            "Multiple assignments to $lhs_var at the same position is not allowed.",
                        )
                    end
                    bit_array[idx...] = true
                end
            end
        end
    end
end

struct NodeInfo end

function build_graph(state::CompileState)
    return g = MetaGraph(DiGraph(), VarName, NodeInfo)
end

##

using JuliaBUGS: program!, CollectVariables, ConstantPropagation, PostChecking

model_def, data, inits =
    Base.Fix1(getfield, JuliaBUGS.BUGSExamples.leuk).([:model_def, :data, :inits]);
inits = first(inits);

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
