FUNCTION_TO_ATTEMPT_EVAL = JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS

function build_eval_function(state::CompileState, statement::Statement; return_expr = false)
    return build_eval_function_inner(state, statement; return_expr = return_expr)
end
function build_eval_function(state::CompileState, for_statement::ForStatement; return_expr = false)
    loop_var_as_args = Any[]
    for loop_var in for_statement.loop_vars
        push!(loop_var_as_args, MacroTools.combinearg(loop_var, :Int, false, nothing))
    end
    return build_eval_function_inner(state, for_statement, loop_var_as_args; return_expr = return_expr)
end
function build_eval_function_inner(state::CompileState, statement, args=Any[]; return_expr = false)
    for var_sym in statement.rhs_vars
        var, type = if var_sym ∈ state.variables_tracked_in_eval_module
            var = getproperty(state.eval_module, var_sym)
            (nothing, typeof(var))
        else
            (nothing, :Any)
        end
        push!(args, MacroTools.combinearg(var_sym, type, false, var))
    end
    def_dict = Dict(
        :name => gensym(string(statement.lhs)),
        :args => args,
        :kwargs => Any[],
        :body => statement.rhs, # TODO: can replace `ref` with `view` to avoid copying
        :whereparams => (),
    )
    def_expr = MacroTools.combinedef(def_dict)
    if return_expr
        return def_expr
    end
    return @RuntimeGeneratedFunction(state.eval_module, def_expr)
end

# `call` assume that number of `loop_var_values` is the same as the number of loop variables in `f`
function call(
    m::Module, f::RuntimeGeneratedFunction{argnames,VTs}, loop_var_values...
) where {argnames,VTs}
    fetched_vars = map(
        arg -> getproperty(m, arg), argnames[(length(loop_var_values) + 1):end]
    )
    args = (loop_var_values..., fetched_vars...)
    return f(args...)
end

function compute_transformed!(state::CompileState)
    new_value_added = true
    statements_to_skip = Set()
    for_statements_to_skip = Set()
    evaluated_logical_for_statement_indices = Dict{Int,BitArray}() # map from for_statement id (index from the vector) to a bit array indexed by the indices of the for_statement
    functions = Dict()
    while new_value_added
        new_value_added = false

        for (i, statement) in enumerate(state.logical_statements)
            if i in statements_to_skip
                continue
            end

            if any(statement.rhs_funs) do fun
                fun ∉ FUNCTION_TO_ATTEMPT_EVAL
            end # the function is not in the list of functions to attempt to evaluate, no hope of evaluating it
                push!(statements_to_skip, i)
                continue
            end

            if any(statement.rhs_vars) do var
                var ∉ state.variables_tracked_in_eval_module
            end # some of the rhs variables that we do not know the value of, just skip now
                continue
            end

            simplified_lhs = statement.lhs # already simplified at construction time

            rhs_value = nothing
            if statement.rhs isa Number
                rhs_value = statement.rhs
            elseif statement.rhs isa Symbol &&
                statement.rhs ∈ state.variables_tracked_in_eval_module
                rhs_value = getproperty(state.eval_module, statement.rhs)
                if !(rhs_value isa Real)
                    throw(
                        ArgumentError(
                            "In BUGS, explicit indexing is required. To access the value of $(statement.rhs), use $(statement.rhs[:]).",
                        ),
                    )
                end
            else
                f = if statement in keys(functions)
                    functions[statement]
                else
                    build_eval_function(state, statement)
                end
                value = nothing
                try
                    value = call(state.eval_module, f)
                catch _
                end # can't evaluate, so just move on
                if value === nothing
                    functions[statement] = f
                    continue
                end
                # check if the value contains missing
                if ismissing(value) || any(ismissing, value)
                    continue
                end
                rhs_value = value
            end

            store_values!(state, simplified_lhs, rhs_value)
            push!(statements_to_skip, i)
            push!(state.excluded_logical_statements, i)
            new_value_added = true
        end

        for (i, for_statement) in enumerate(state.logical_for_statements)
            if i in for_statements_to_skip
                continue
            end

            if any(for_statement.rhs_funs) do fun
                fun ∉ FUNCTION_TO_ATTEMPT_EVAL
            end
                push!(for_statements_to_skip, i)
                continue
            end

            if any(for_statement.rhs_vars) do var
                var ∉ state.variables_tracked_in_eval_module
            end
                continue
            end

            evaluated_indices_array = get!(
                evaluated_logical_for_statement_indices,
                i,
                falses(state.array_sizes[for_statement.lhs.args[1]]...),
            )

            for indices in Iterators.product(for_statement.bounds...)
                if evaluated_indices_array[indices...]
                    continue
                end

                simplified_lhs = simplify_lhs(
                    merge(state.data, NamedTuple{for_statement.loop_vars}(Tuple(indices))),
                    for_statement.lhs,
                )

                rhs_value = nothing
                if for_statement.rhs isa Number
                    rhs_value = for_statement.rhs
                elseif for_statement.rhs isa Symbol &&
                    for_statement.rhs ∈ state.variables_tracked_in_eval_module
                    rhs_value = getproperty(state.eval_module, for_statement.rhs)
                    if !(rhs_value isa Real)
                        throw(
                            ArgumentError(
                                "In BUGS, explicit indexing is required. To access the value of $(statement.rhs), use $(statement.rhs[:]).",
                            ),
                        )
                    end
                else
                    f = if for_statement in keys(functions)
                        functions[for_statement]
                    else
                        build_eval_function(state, for_statement)
                    end
                    value = nothing
                    try
                        value = call(state.eval_module, f, indices...)
                    catch _
                    end # can't evaluate, so just move on
                    if value === nothing
                        functions[for_statement] = f
                        continue
                    end
                    rhs_value = value
                end

                store_values!(state, simplified_lhs, rhs_value)
                evaluated_indices_array[indices...] = true
                new_value_added = true
            end

            if i in keys(evaluated_logical_for_statement_indices) &&
                all(evaluated_logical_for_statement_indices[i])
                push!(for_statements_to_skip, i)
                push!(state.excluded_logical_for_statements, i)
                delete!(evaluated_logical_for_statement_indices, i)
            end
        end
    end

    # convert Array{Union{Missing, T}} to Array{T} if all the values are not missing
    # TODO: this can be expensive
    for var in state.variables_tracked_in_eval_module
        arr = getproperty(state.eval_module, var)
        if !(arr isa AbstractArray) || !(Missing <: eltype(arr))
            continue
        end
        if all(!ismissing, arr)
            setproperty!(state.eval_module, var, Missings.disallowmissing(arr))
        end
    end
end

function store_values!(
    state::CompileState, simplified_lhs::Symbol, value::Union{Int,Float64}
)
    if simplified_lhs ∈ state.variables_tracked_in_eval_module
        throw(
            ErrorException(
                "$simplified_lhs already has a value, `check_multiple_assignments` should prevent this but didn't.",
            ),
        )
    end
    push!(state.variables_tracked_in_eval_module, simplified_lhs)
    state.eval_module.eval(:($(simplified_lhs) = $(value)))
    return nothing
end
function store_values!(state::CompileState, simplified_lhs::Expr, value::Union{Int,Float64})
    @capture(simplified_lhs, lhs_var_[indices__])
    if lhs_var ∉ state.variables_tracked_in_eval_module
        push!(state.variables_tracked_in_eval_module, lhs_var)
        arr = fill(missing, state.array_sizes[lhs_var]...)
        setproperty!(state.eval_module, lhs_var, arr)
    end
    push!(state.variables_tracked_in_eval_module, lhs_var)
    array = getproperty(state.eval_module, lhs_var)
    setproperty!(state.eval_module, lhs_var, setindex!!(array, value, indices...))
    return nothing
end
function store_values!(state::CompileState, simplified_lhs::Expr, value::AbstractArray)
    @capture(simplified_lhs, lhs_var_[indices__])
    if lhs_var ∉ state.variables_tracked_in_eval_module
        push!(state.variables_tracked_in_eval_module, lhs_var)
        arr = fill(missing, state.array_sizes[lhs_var]...)
        setproperty!(state.eval_module, lhs_var, arr)
    elseif lhs_var ∈ keys(state.data) # `variables_tracked_in_eval_module` is a superset of `keys(data)` 
        # special case: data array contains missing values, then we need to make a copy before mutating
        if getproperty(state.eval_module, lhs_var) === state.data[lhs_var] # haven't been copied
            arr = copy(state.data[lhs_var])
            setproperty!(state.eval_module, lhs_var, arr)
        end
    end
    array = getfield(state.eval_module, lhs_var)
    setproperty!(state.eval_module, lhs_var, setindex!!(array, value, indices...))
    return nothing
end
