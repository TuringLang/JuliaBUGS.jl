FUNCTION_TO_ATTEMPT_EVAL = JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS # TODO: some of the BUGS functions may be too expensive too

# initialize the variables that are not data or transformed variables as missing
function initialize_variables(state::CompileState)
    for k in keys(state.array_sizes)
        if k ∉ state.variables_tracked_in_eval_module
            setproperty!(state.eval_module, k, fill(missing, state.array_sizes[k]...))
        end
    end
    scalars = Set()
    for stmt in all_statements(state)
        for rhs_var in stmt.rhs_vars
            if rhs_var ∉ keys(state.array_sizes)
                push!(scalars, rhs_var)
            end
        end
    end
    for scalar in scalars
        if scalar ∉ state.variables_tracked_in_eval_module
            setproperty!(state.eval_module, scalar, missing)
        end
    end
end

# similar to non-standard interpretation, instead of evaluating the function, we just return the dependencies
function build_dependencies_eval_function(
    state::CompileState, stmt::Union{<:Statement,<:ForStatement}; return_expr=false
)
    expr = SemanticAnalysis.build_eval_function(state, stmt; return_expr=true)

    #! format: off
    @capture(expr, function F_(Args__)
        body_
    end)
    #! format: on

    ex = MacroTools.postwalk(body) do sub_expr
        if MacroTools.@capture(sub_expr, v_[indices__])
            _indices_name = gensym("indices")
            _e = MacroTools.@q begin
                $(_indices_name) = Any[$(indices...)]
                non_evaled_indices = findall(ismissing, $(_indices_name))
                if !isempty(non_evaled_indices)
                    array_size = $(state.array_sizes[v])
                    for i in non_evaled_indices
                        $(_indices_name)[i] = 1:array_size[i]
                    end
                    push!(deps, ($(Meta.quot(v)), $(_indices_name)...))
                    missing
                else
                    val = $v[$(_indices_name)...]
                    if ismissing(val) || any(ismissing, val)
                        push!(deps, ($(Meta.quot(v)), $(_indices_name)...))
                    end
                    # TODO: can val be array of missings?
                    val
                end
            end
            return _e
        elseif @capture(sub_expr, f_(args__))
            _new_args = Any[]
            _stmts = Any[]
            for arg in args
                fresh_var_name = gensym()
                _e = MacroTools.@q begin
                    $(fresh_var_name) = $(arg)
                end
                push!(_new_args, fresh_var_name)
                push!(_stmts, _e)
            end
            if f in FUNCTION_TO_ATTEMPT_EVAL ∪ (:(+), :(-), :(*), :(\), :(:), :(^))
                return Expr(
                    :block,
                    _stmts...,
                    MacroTools.@q(
                        if (any(ismissing, [$(_new_args...)]))
                            missing
                        else
                            $f($(_new_args...))
                        end
                    )
                )
            else
                return Expr(:block, _stmts..., :missing) # if we don't recognize the function, we don't evaluate it
            end
        end
        sub_expr
    end

    ret_ex = MacroTools.@q function $(F)($(Args...))
        deps = Any[]
        $ex
        return deps
    end

    if return_expr
        return ret_ex
    else
        return @RuntimeGeneratedFunction(ret_ex)
    end
end

# need to decide if the variable is observed 
function build_dep_graph(state::CompileState)
    initialize_variables(state)
    g = MetaGraph(
        DiGraph(); label_type=Union{Symbol,Tuple{Symbol,Vararg{Int}}}, vertex_data_type=Int
    )
    array_vars = collect(keys(state.array_sizes))
    for (i, stmt) in enumerate(all_statements(state))
        if stmt isa Statement
            lhs_label = stmt.lhs isa Symbol ? stmt.lhs : Tuple(stmt.lhs.args...)

            lhs_val = get_value(state, lhs_label)
            if is_logical(stmt)
                if lhs_val isa AbstractArray
                    if all(!ismissing, lhs_val)
                        continue
                    end
                else
                    if !ismissing(lhs_val)
                        continue
                    end
                end
            end
            g[lhs_label] = i

            rhs_scalars = [rhs_var for rhs_var in stmt.rhs_vars if rhs_var ∉ array_vars]
            _rhs_array_vars = [
                rhs_var for rhs_var in stmt.rhs_vars if rhs_var in array_vars
            ]
            rhs_array_vars = if isempty(_rhs_array_vars) || stmt.rhs isa Union{Symbol,Real}
                []
            else
                f = build_dependencies_eval_function(state, stmt)
                call(state.eval_module, f)
            end

            for rhs_var in rhs_scalars
                if !haskey(g, rhs_var)
                    g[rhs_var] = 0
                end
                add_edge_fail!(g, rhs_var, lhs_label)
            end
            for rhs_var in rhs_array_vars
                for i in Iterators.product(rhs_var[2:end])
                    rhs_var_label = (rhs_var, i...)
                    if !haskey(g, rhs_var_label)
                        g[rhs_var_label] = 0
                    end
                    add_edge_fail!(g, rhs_var_label, lhs_label)
                end
            end
        else # stmt isa ForStatement
            rhs_scalars = [rhs_var for rhs_var in stmt.rhs_vars if rhs_var ∉ array_vars]

            for rhs_var in rhs_scalars
                if !haskey(g, rhs_var)
                    g[rhs_var] = 0
                end
            end

            f = if stmt.rhs isa Union{Symbol,Real}
                nothing # not used
            else
                build_dependencies_eval_function(state, stmt)
            end

            _rhs_array_vars = [
                rhs_var for rhs_var in stmt.rhs_vars if rhs_var in array_vars
            ]

            for indices in Iterators.product(stmt.bounds...)
                simplified_lhs = simplify_lhs(
                    merge(state.data, NamedTuple{stmt.loop_vars}(Tuple(indices))), stmt.lhs
                )

                lhs_label = Tuple(simplified_lhs.args)

                lhs_val = get_value(state, lhs_label)
                if is_logical(stmt)
                    if lhs_val isa AbstractArray
                        if all(!ismissing, lhs_val)
                            continue
                        end
                    else
                        if !ismissing(lhs_val)
                            continue
                        end
                    end
                end

                g[lhs_label] = i

                rhs_array_vars =
                    if isempty(_rhs_array_vars) || stmt.rhs isa Union{Symbol,Real}
                        []
                    else
                        call(state.eval_module, f, indices...)
                    end

                for rhs_var in rhs_scalars
                    add_edge_fail!(g, rhs_var, lhs_label)
                end

                for rhs_var in rhs_array_vars
                    is = [i isa Int ? UnitRange(i, i) : i for i in rhs_var[2:end]]

                    for i in Iterators.product(is...)
                        rhs_var_label = (rhs_var[1], i...)
                        if !haskey(g, rhs_var_label)
                            g[rhs_var_label] = 0
                        end

                        add_edge_fail!(g, rhs_var_label, lhs_label)
                    end
                end
            end
        end
    end

    # TODO: why does this fail?
    # # if a variable data is 0, then it is a data variable and we don't need to track it
    # for vertex_label in labels(g)
    #     if g[vertex_label] == 0
    #         delete!(g, vertex_label)
    #     end
    # end

    return g
end

function get_value(state::CompileState, var_label::Symbol)
    return getproperty(state.eval_module, var_label)
end
function get_value(state::CompileState, var_label::Tuple{Symbol,Vararg{Int}})
    return getproperty(state.eval_module, var_label[1])[var_label[2:end]...]
end

function add_edge_fail!(g, from, to)
    if !add_edge!(g, from, to)
        error("edge can't be add from $from to $to")
    end
end
