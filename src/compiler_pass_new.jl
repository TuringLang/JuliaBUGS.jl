using JuliaBUGS, MacroTools
using JuliaBUGS: Var, Scalar, ArrayElement, ArrayVar, to_varname
using JuliaBUGS: evaluate, check_idxs, find_variables_on_lhs, is_resolved, should_skip_eval
using BangBang
using DynamicPPL
using MetaGraphsNext, Graphs
using Setfield

is_resolved(::T) where {T} = T <: Union{Number,Colon,UnitRange,Array{<:Number}}

# TODO: this `evaluate` function can be compiled if env is NamedTuple(we can actually create an env also include the type of the values)
# also find a way to include the function names in the type
# use lowered to check if compiled
function evaluate(
    env,
    expr;
    module_name=Main,
    allow_internal_functions=false,
    internal_functions=JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS,
    arithmetic_functions=(:*, :+, :-, :/, :^),
    allowed_functions=if allow_internal_functions
        arithmetic_functions ∪ internal_functions
    else
        arithmetic_functions
    end,
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
            expr = Expr(:ref, expr.args[1], map(Base.Fix1(evaluate, env), expr.args[2:end])...)
            if !haskey(env, expr.args[1]) || any(Base.Fix1(isa, Expr), expr.args[2:end])
                return expr
            end
            @assert all(Base.Fix1(isa, Union{Int,UnitRange{Int}}), expr.args[2:end])
            value = getindex(env[expr.args[1]], expr.args[2:end]...)
            if ismissing(value) || any(ismissing, value)
                return expr
            else
                return value
            end
        elseif Meta.isexpr(expr, :call)
            expr = Expr(:call, expr.args[1], map(Base.Fix1(evaluate, env), expr.args[2:end])...)
            if expr.args[1] == :(:)
                return (:)(expr.args[2:end]...)
            elseif expr.args[1] ∈ allowed_functions
                return (getfield(module_name, expr.args[1]))(expr.args[2:end]...)
            else
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

# E is either = or ~
mutable struct Statement{E}
    lhs
    rhs
end

function Statement(@nospecialize(expr))
    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    @assert sign ∈ (:~, :(=))
    return Statement{sign}(lhs, rhs)
end

mutable struct ForStatement{E}
    nested_levels::Int
    loop_vars::Vector{Symbol}
    loop_vars_lens::Vector{Dict{Symbol,Vector{<:Lens}}}
    bounds
    lhs
    rhs
end

function ForStatement(@nospecialize(expr))
    nested_levels = 0
    loop_vars = []
    bounds = []
    while Meta.isexpr(expr, :for)
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
    loop_vars_lens = grab_loop_var_as_lens(expr, loop_vars)
    return ForStatement{sign}(nested_levels, loop_vars, loop_vars_lens, bounds, lhs, rhs)
end

function evaluate_loop_bounds!(for_statement::ForStatement, data)
    for (i, bound) in enumerate(for_statement.bounds)
        bound = evaluate(bound, data)
        @assert bound isa UnitRange
        for_statement.bounds[i] = bound
    end
end

struct CompileState
    data
    initializations
    transformed_variables

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
        initializations,
        Dict(),
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
    data = state.data
    # only look at the LHS
    for (k, v) in pairs(data) # size of data arrays are known, initializations is treated after compilation
        if v isa Array
            state.array_sizes[k] = size(v)
        end
    end

    for statement in vcat(state.logical_statements, state.stochastic_statements)
        lhs = find_variables_on_lhs(statement.lhs, data)
        if is_resolved(evaluate(lhs, data)) && is_logical(statement)
            error("$lhs is specified at data, thus can't be assigned to.")
        end
        if lhs isa Scalar
            push!(state.scalars, lhs)
        else
            check_idxs(lhs.name, lhs.indices, data)
            if haskey(data, lhs.name)
                @assert length(data[lhs.name]) == length(last.(lhs.indices)) &&
                    all(last.(v.indices) .<= size(data[v.name]))
                continue
            end
            if haskey(state.array_sizes, lhs.name)
                state.array_sizes[lhs.name] =
                    max.(state.array_sizes[lhs.name], last.(lhs.indices)) # check ndims implicitly
            else
                state.array_sizes[lhs.name] = [last.(lhs.indices)...]
            end
        end
    end

    for for_statement in vcat(state.logical_for_statements, state.stochastic_for_statements)
        for indices in Iterators.product(for_statement.bounds...)
            lhs = for_statement.lhs
            for (loop_var, value) in zip(for_statement.loop_vars, indices)
                for lens in for_statement.loop_vars_lens[loop_var]
                    lhs = set(lhs, lens, value)
                end
            end
            lhs = find_variables_on_lhs(lhs, data)
            if lhs isa Scalar
                error("Scalar definition inside a loop is not supported.")
            else
                check_idxs(lhs.name, lhs.indices, data)
                if haskey(data, lhs.name)
                    @assert ndims(data[lhs.name]) == length(last.(lhs.indices)) &&
                        all(last.(lhs.indices) .<= size(data[lhs.name]))
                    continue
                end
                if haskey(state.array_sizes, lhs.name)
                    state.array_sizes[lhs.name] =
                        max.(state.array_sizes[lhs.name], last.(lhs.indices)) # check ndims implicitly
                else
                    state.array_sizes[lhs.name] = [last.(lhs.indices)...]
                end
            end
        end
    end
    concretize_colon_indexing!(state)
end

function concretize_colon_indexing!(state::CompileState)
    for collection in (
        state.logical_statements,
        state.stochastic_statements,
        state.logical_for_statements,
        state.stochastic_for_statements,
    )
        for statement in collection # TODO: verify that this actually mutate the statement
            statement.rhs = MacroTools.postwalk(statement.rhs) do sub_expr
                if MacroTools.@capture(sub_expr, x_[indices__])
                    return :(x[$(
                        [
                            idx == :(:) ? :(1:($(state.array_sizes[x][i]))) : idx for
                            (i, idx) in enumerate(indices)
                        ]...
                    )])
                end
                sub_expr
            end
        end
    end
end

# a variable is uniquely identified by expression id and loop var bindings
function grab_loop_var_as_lens(expr, loop_vars)
    lenses_map = Dict()
    for loop_var in loop_vars
        lenses = find_lens(expr, loop_var, Setfield.IdentityLens())
        @assert !isempty(lenses)
        lenses_map[loop_var] = lenses
    end
    return lenses_map
end

function find_lens(expr, target_expr, parent_lens)
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
            child_lenses = find_lens(arg, target_expr, parent_lens ∘ (@lens _.args[i]))
            for lens in child_lenses
                push!(lenses, lens)
            end
        end
    end
    return lenses
end

function compute_transformed_variables!(state::CompileState)
    data = state.data
    new_value_added = true

    while new_value_added
        new_value_added = false
        for statement in state.logical_statements
            if should_skip_eval(statement.rhs)
                continue
            end

            lhs = find_variables_on_lhs(statement.lhs, data)

            if haskey(state.transformed_variables, lhs.name)
                if lhs isa Scalar ||
                    !ismissing(state.transformed_variables[lhs.name][lhs.indices...])
                    continue
                else
                    local_env = merge(copy(Dict(pairs(data))), state.transformed_variables)
                    value = evaluate(statement.rhs, local_env)
                    if is_resolved(value)
                        state.transformed_variables[lhs.name][lhs.indices...] = value
                        new_value_added = true
                    end
                end
            else
                local_env = merge(copy(Dict(pairs(data))), state.transformed_variables)
                value = evaluate(statement.rhs, local_env)
                if is_resolved(value)
                    if lhs isa Scalar
                        state.transformed_variables[lhs.name] = value
                    else
                        state.transformed_variables[lhs.name] = fill(
                            missing, state.array_sizes[lhs.name]...
                        )
                        state.transformed_variables[lhs.name] = setindex!!(
                            state.transformed_variables[lhs.name], value, lhs.indices...
                        )
                    end
                    new_value_added = true
                end
            end
        end

        for for_statement in state.logical_for_statements
            for indices in Iterators.product(for_statement.bounds...)
                local_env = merge(copy(Dict(pairs(data))), state.transformed_variables)
                for (loop_var, bounds) in zip(for_statement.loop_vars, indices)
                    local_env[loop_var] = bounds
                end
                lhs = find_variables_on_lhs(for_statement.lhs, local_env)
                if haskey(state.transformed_variables, lhs.name)
                    if !ismissing(state.transformed_variables[lhs.name][lhs.indices...])
                        continue
                    else
                        value = evaluate(for_statement.rhs, local_env)
                        if is_resolved(value)
                            setindex!!(
                                state.transformed_variables[lhs.name], value, lhs.indices...
                            )
                            new_value_added = true
                        end
                    end
                else
                    value = evaluate(for_statement.rhs, local_env)
                    if is_resolved(value)
                        if lhs isa Scalar
                            state.transformed_variables[lhs.name] = value
                        else
                            state.transformed_variables[lhs.name] = fill(
                                missing, state.array_sizes[lhs.name]...
                            )
                            state.transformed_variables[lhs.name] = setindex!!(
                                state.transformed_variables[lhs.name], value, lhs.indices...
                            )
                        end
                    end
                end
            end
        end
    end

    for (k, v) in pairs(state.transformed_variables)
        if v isa Array
            state.transformed_variables[k] = identity.(v)
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
                    local_env = merge(copy(Dict(pairs(data))), state.transformed_variables)
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
                            if haskey(state.transformed_variables, lhs_var) &&
                                !ismissing(state.transformed_variables[lhs_var][idx...]) &&
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
                        if haskey(state.transformed_variables, lhs_var) &&
                            !ismissing(state.transformed_variables[lhs_var][idx...]) &&
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

struct NodeInfo
    is_logical
    expression_id
    loop_var_bindings
end

# function build_graph(state::CompileState)
#     g = MetaGraph(DiGraph(), VarName, NodeInfo)

#     env = merge(copy(Dict(pairs(state.data))), state.transformed_variables)

#     for statement in state.logical_statements
#         lhs = find_variables_on_lhs(statement.lhs, env)
#         if is_resolved(evaluate(lhs, transformed_variables)) # meaning we already evaluated it
#             continue
#         end
#         statement.rhs = concretize_colon_indexing(statement.rhs, state.array_sizes, env)

#         rhs = evaluate(statement.rhs, env)

#         if rhs isa Symbol || ()
#             @assert lhs isa Union{Scalar,ArrayElement}
#             rhs = Var(rhs)

#         elseif Meta.isexpr(rhs, :ref) &&
#             all(x -> x isa Union{Number,UnitRange}, rhs.args[2:end])
#             rhs_var = Var(rhs.args[1], Tuple(rhs.args[2:end]))
#             rhs_array_var = create_array_var(rhs_var.name, pass.array_sizes, env)
#             size(rhs_var) == size(lhs_var) ||
#                 error("Size mismatch between lhs and rhs at expression $expr")
#             if lhs_var isa ArrayElement
#                 @assert pass.array_bitmap[rhs_var.name][rhs_var.indices...] "Variable $rhs_var is not defined."
#                 node_function = MacroTools.@q ($(rhs_var.name)::Array) ->
#                     $(rhs_var.name)[$(rhs_var.indices...)]
#                 node_args = [rhs_array_var]
#                 dependencies = [rhs_var]
#             else
#                 # rhs is not evaluated into a concrete value, then at least some elements of the rhs array are not data
#                 non_data_vars = filter(x -> x isa Var, evaluate(rhs_var, env))
#                 # for now: evaluate(rhs_var, env) will produce scalarized `Var`s, so dependencies
#                 # may contain `Auxiliary Nodes`, this should be okay, but maybe we should keep things uniform
#                 # by keep `dependencies` only variables in the model, not auxiliary nodes
#                 for v in non_data_vars
#                     @assert pass.array_bitmap[v.name][v.indices...] "Variable $v is not defined."
#                 end
#                 node_function = MacroTools.@q ($(rhs_var.name)::Array) ->
#                     $(rhs_var.name)[$(rhs_var.indices...)]
#                 node_args = [rhs_array_var]
#                 dependencies = non_data_vars
#             end
#         else
#             rhs_expr = replace_constants_in_expr(rhs_expr, env)
#             evaled_rhs, dependencies, node_args = evaluate_and_track_dependencies(rhs_expr, env)

#             # TODO: since we are not evaluating the node function expressions anymore, we don't have to store the expression like anonymous functions 
#             # rhs can be evaluated into a concrete value here, because including transformed variables in the data
#             # is effectively constant propagation
#             if is_resolved(evaled_rhs)
#                 node_function = Expr(:(->), Expr(:tuple), Expr(:block, evaled_rhs))
#                 node_args = []
#                 # we can also directly save the evaled variable to `env` and later convert to var_store
#                 # issue is that we need to do this in steps, const propagation need to a separate pass
#                 # otherwise the variable in previous expressions will not be evaluated to the concrete value
#             else
#                 dependencies, node_args = map(
#                     x -> map(x) do x_elem
#                         if x_elem isa Symbol
#                             return Var(x_elem)
#                         elseif x_elem isa Tuple && last(x_elem) == ()
#                             return create_array_var(first(x_elem), pass.array_sizes, env)
#                         else
#                             return Var(first(x_elem), last(x_elem))
#                         end
#                     end,
#                     map(collect, (dependencies, node_args)),
#                 )

#                 rhs_expr = MacroTools.postwalk(rhs_expr) do sub_expr
#                     if @capture(sub_expr, arr_[idxs__])
#                         new_idxs = [
#                             idx isa Integer ? idx : :(JuliaBUGS.try_cast_to_int($(idx))) for
#                             idx in idxs
#                         ]
#                         return Expr(:ref, arr, new_idxs...)
#                     end
#                     return sub_expr
#                 end

#                 args = convert(Array{Any}, deepcopy(node_args))
#                 for (i, arg) in enumerate(args)
#                     if arg isa ArrayVar
#                         args[i] = Expr(:(::), arg.name, :Array)
#                     elseif arg isa Scalar
#                         args[i] = arg.name
#                     else
#                         error("Unexpected argument type: $arg")
#                     end
#                 end
#                 node_function = Expr(:(->), Expr(:tuple, args...), rhs_expr)
#             end
#         end

# end

##
using JuliaBUGS: program!, CollectVariables, ConstantPropagation

model_def, data, inits =
    Base.Fix1(getfield, JuliaBUGS.BUGSExamples.leuk).([:model_def, :data, :inits]);
inits = first(inits);

scalars, array_sizes = program!(CollectVariables(), model_def, data)

has_new_val, transformed_variables = program!(
    ConstantPropagation(scalars, array_sizes), model_def, data
)
while has_new_val
    has_new_val, transformed_variables = program!(
        ConstantPropagation(false, transformed_variables), model_def, data
    )
end

transformed_variables

state = CompileState(model_def)
determine_array_sizes!(state, data)
compute_transformed_variables!(state, data)

model_def = @bugs begin
    for i in 1:3
        x[i] = y[i]
    end

    for i in 1:10
        x[i] ~ Normal(0, 1)
    end
end

state = CompileState(model_def, (y=[1, 2, 3],), NamedTuple())

state = CompileState(model_def, (;), NamedTuple())

determine_array_sizes!(state)
compute_transformed_variables!(state)

check_multiple_assignments(state)
