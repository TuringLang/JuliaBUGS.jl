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
    evaluated_logical_for_statement_indices = Dict{Int,BitArray}()
    functions = Dict()
    while new_value_added
        new_value_added = false

        for (i, statement) in enumerate(state.logical_statements)
            if i in statements_to_skip
                continue
            end

            if any(statement.rhs_funs) do fun
                fun ∉ FUNCTION_TO_ATTEMPT_EVAL
            end
                push!(statements_to_skip, i)
                continue
            end

            if any(statement.rhs_vars) do var
                var ∉ state.variables_tracked_in_eval_module
            end
                continue
            end

            simplified_lhs = simplify_lhs(state.data, statement.lhs)

            if statement.rhs isa Number
                store_values!(state, simplified_lhs, statement.rhs)
                push!(statements_to_skip, i)
                new_value_added = true
                continue
            elseif statement.rhs isa Symbol && hasproperty(state.eval_module, statement.rhs)
                rhs_value = getproperty(state.eval_module, statement.rhs)
                if !rhs_value isa Real
                    throw(ArgumentError("In BUGS, explicit indexing is required. To access the value of $(statement.rhs), use $(statement.rhs[:])."))
                end
                store_values!(state, simplified_lhs, rhs_value)
                push!(statements_to_skip, i)
                new_value_added = true
                continue 
            else # Expr
                f = build_eval_function(state, statement)
                try
                    rhs_value = call(state.eval_module, f)
                catch _ # can't evaluate, so just move on
                    functions[statement] = f
                    continue
                end

                # check if the value contains missing
                if reduce(ismissing, rhs_value, init=false)
                    continue
                end

                simplified_lhs = simplify_lhs(state.data, statement.lhs)
                
                if simplified_lhs isa Symbol
                    Base.eval(RHSEval, :($(simplified_lhs) = $(rhs_value)))
                    push!(statements_to_skip, i)
                    new_value_added = true
                else # Expr
                    store_values!(state, simplified_lhs, rhs_value)
                    push!(statements_to_skip, i)
                    new_value_added = true
                end
            end
        end

        # TODO: how about missings?

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

        setproperty!(
            RHSEval, lhs_var, setindex!!(getfield(RHSEval, lhs_var), value, indices...)
        )
        return true
    else # catch other possible types by evaluating other functions
        return false
    end
end
# TODO: check assign array to scalar