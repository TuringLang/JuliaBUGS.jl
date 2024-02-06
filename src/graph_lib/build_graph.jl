

# similar to non-standard interpretation, instead of evaluating the function, we just return the dependencies
function gen_func(state, stmt)
    expr = SemanticAnalysis.build_eval_function(state, stmt; return_expr=true)

    @capture(expr, function F_(Args__) body_ end)

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
                    push!(deps, ($(Meta.quot(v)), $(_indices_name)...))
                    ($v)[$(_indices_name)...]
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
            return Expr(:block, _stmts..., Expr(:call, f, _new_args...))
        end
        sub_expr
    end

    return MacroTools.@q function $(F)($(Args...)) 
        deps = Any[]
        $ex
        return deps
    end
end

# need to decide if the variable is observed 
function build_dep_graph(state::CompileState)
    values_map = SemanticAnalysis.get_data_and_transformed_variables(state)
    for k in keys(state.array_sizes)
        if k ∉ keys(values_map)
            state.array_sizes[k] = fill(missing, state.array_sizes[k]...)
        end
    end

    g = MetaGraph(DiGraph(); label_type=NTuple, vertex_data_type=Any)
    # statement_id also index into vector of node functions

    for (i, stmt) in enumerate(not_for_statements(state))
        if stmt.lhs isa Symbol
            add_vertex!(g, (stmt.lhs, nothing))
        else
            add_vertex!(g, (stmt.lhs.args...))
        end
    end
end