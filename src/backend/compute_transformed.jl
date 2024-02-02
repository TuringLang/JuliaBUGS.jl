FUNCTION_TO_ATTEMPT_EVAL = JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS

function build_eval_function(state::CompileState, statement::Statement)
    return build_eval_function_inner(state, statement)
end
function build_eval_function(state::CompileState, for_statement::ForStatement)
    loop_var_as_args = Any[]
    for loop_var in for_statement.loop_vars
        push!(loop_var_as_args, MacroTools.combinearg(loop_var, :Int, false, nothing))
    end
    return build_eval_function_inner(state, for_statement, loop_var_as_args)
end
function build_eval_function_inner(state::CompileState, statement, args=Any[])
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
    return @RuntimeGeneratedFunction(state.eval_module, def_expr)
end

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
    statements_to_skip = state.excluded_logical_statements
    for_statements_to_skip = state.excluded_logical_for_statements
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

            simplified_lhs = simplify_lhs(state.data, statement.lhs)

            rhs_value = if statement.rhs isa Number
                statement.rhs
            elseif statement.rhs isa Symbol && statement.rhs ∈ state.variables_tracked_in_eval_module
                getproperty(state.eval_module, statement.rhs)
                if !rhs_value isa Real
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
                try
                    value = call(state.eval_module, f)
                catch _ # can't evaluate, so just move on
                    functions[statement] = f
                    continue
                end
                # check if the value contains missing
                if ismissing(x) || any(value) do x
                    return ismissing(x)
                end
                    continue
                end
                value
            end

            store_values!(state, simplified_lhs, rhs_value)
            push!(statements_to_skip, i)
            new_value_added = true
        end

        for (i, for_statement) in enumerate(state.logical_for_statements)
            if i in for_statements_to_skip
                continue
            end

            if i in keys(evaluated_logical_for_statement_indices)
                if all(evaluated_logical_for_statement_indices[i])
                    push!(for_statements_to_skip, i)
                    delete!(evaluated_logical_for_statement_indices, i)
                    continue
                end
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
    push!(state.variables_tracked_in_eval_module, lhs_var)
    state.eval_module.eval(:($(simplified_lhs) = $(value)))
    return nothing
end
function store_values!(state::CompileState, simplified_lhs::Expr, value::Union{Int,Float64})
    @capture(simplified_lhs, lhs_var_[indices__])
    if lhs_var ∉ state.variables_tracked_in_eval_module
        push!(state.variables_tracked_in_eval_module, lhs_var)
        state.eval_module.eval(
            :($lhs_var = $(fill(missing, state.array_sizes[lhs_var]...)))
        )
    end
    push!(state.variables_tracked_in_eval_module, lhs_var)
    array = getfield(state.eval_module, lhs_var)
    setproperty!(state.eval_module, lhs_var, setindex!!(array, value, indices...))
    return nothing
end
function store_values!(state::CompileState, simplified_lhs::Expr, value::AbstractArray)
    @capture(simplified_lhs, lhs_var_[indices__])
    if lhs_var ∉ state.variables_tracked_in_eval_module
        push!(state.variables_tracked_in_eval_module, lhs_var)
        state.eval_module.eval(
            :($lhs_var = $(fill(missing, state.array_sizes[lhs_var]...)))
        )
    elseif lhs_var ∈ keys(state.data) # `variables_tracked_in_eval_module` is a superset of `keys(data)` 
        # special case: data array contains missing values, then we need to make a copy before mutating
        if getfield(RHSEval, lhs_var) === state.data[lhs_var] # haven't been copied
            state.eval_module.eval(:($lhs_var = $(copy(state.data[lhs_var]))))
        end
    end
    array = getfield(state.eval_module, lhs_var)
    setproperty!(state.eval_module, lhs_var, setindex!!(array, value, indices...))
    return nothing
end
