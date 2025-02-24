function _build_stmt_to_stmt_id(
    block_expr, stmt_to_stmt_id=IdDict{Expr,Int}(), next_id=Ref(1)
)
    @assert Meta.isexpr(block_expr, :block)
    for statement in block_expr.args
        if Meta.isexpr(statement, (:(=), :call))
            stmt_to_stmt_id[statement] = next_id[]
            next_id[] += 1
        elseif Meta.isexpr(statement, :for)
            stmt_to_stmt_id = _build_stmt_to_stmt_id(
                statement.args[2], stmt_to_stmt_id, next_id
            )
        end
    end
    return stmt_to_stmt_id
end

# like deepcopy, but stop at :(=) and :call level (:call in :for don't matter)
function _copy_model_def(model_def, new_model_def=Expr(:block))
    @assert Meta.isexpr(model_def, :block)
    for statement in model_def.args
        if Meta.isexpr(statement, (:(=), :call))
            push!(new_model_def.args, statement)
        elseif Meta.isexpr(statement, :for)
            # Recursively copy the inner block of the for-loop.
            new_body = _copy_model_def(statement.args[2], Expr(:block))
            new_for = Expr(:for, statement.args[1], new_body)
            push!(new_model_def.args, new_for)
        else
            # For any other kind of expression, simply include it as is.
            push!(new_model_def.args, statement)
        end
    end
    return new_model_def
end

function _build_stmt_id_to_stmt(stmt_to_stmt_id::IdDict{Expr,Int})
    stmt_id_to_stmt = IdDict{Int,Expr}()
    for (stmt, stmt_id) in stmt_to_stmt_id
        stmt_id_to_stmt[stmt_id] = stmt
    end
    return stmt_id_to_stmt
end

struct StatementIdAttributePass{ET} <: CompilerPass
    all_variables_in_graph::Set{VarName}
    stmt_ids::IdDict{Expr,Int}
    env::ET

    var_to_stmt_id::Dict{VarName,Int}
end

function analyze_statement(
    pass::StatementIdAttributePass, expr::Expr, loop_variables::NamedTuple
)
    lhs_expression = is_deterministic(expr) ? expr.args[1] : expr.args[2]
    merged_env = merge(pass.env, loop_variables)
    simplified_lhs = simplify_lhs(merged_env, lhs_expression)
    varname = if simplified_lhs isa Symbol
        VarName{simplified_lhs}()
    else
        symbol, indices... = simplified_lhs
        VarName{symbol}(IndexLens(indices))
    end

    if varname in pass.all_variables_in_graph
        pass.var_to_stmt_id[varname] = pass.stmt_ids[expr]
    end
    return nothing
end

function _build_var_to_stmt_id(model::BUGSModel, stmt_ids::IdDict{Expr,Int})
    pass = StatementIdAttributePass(
        Set(labels(model.g)), stmt_ids, model.evaluation_env, Dict{VarName,Int}()
    )
    analyze_block(pass, model.model_def)
    return pass.var_to_stmt_id
end

# coarse graph may contains nodes whose degree is 0, these are transformed data
function _build_coarse_dep_graph(
    model::BUGSModel, stmt_to_stmt_id::IdDict{Expr,Int}, var_to_stmt_id::Dict{VarName,Int}
)
    fine_graph = model.g
    coarse_graph = Graphs.SimpleDiGraph(length(stmt_to_stmt_id))
    for edge in Graphs.edges(fine_graph.graph)
        src_varname = label_for(fine_graph, src(edge))
        dst_varname = label_for(fine_graph, dst(edge))
        src_stmt_id = var_to_stmt_id[src_varname]
        dst_stmt_id = var_to_stmt_id[dst_varname]
        add_edge!(coarse_graph, src_stmt_id, dst_stmt_id)
    end
    return coarse_graph
end

function _copy_and_remove_stmt_with_degree_0(
    model_def, stmt_to_stmt_id, coarse_graph, new_model_def=Expr(:block)
)
    @assert Meta.isexpr(model_def, :block)
    for statement in model_def.args
        if Meta.isexpr(statement, (:(=), :call))
            if degree(coarse_graph, stmt_to_stmt_id[statement]) != 0
                push!(new_model_def.args, statement)
            end
        elseif Meta.isexpr(statement, :for)
            # Recursively copy the inner block of the for-loop.
            new_body = _copy_and_remove_stmt_with_degree_0(
                statement.args[2], stmt_to_stmt_id, coarse_graph, Expr(:block)
            )
            new_for = Expr(:for, statement.args[1], new_body)
            push!(new_model_def.args, new_for)
        else
            # For any other kind of expression, simply include it as is.
            push!(new_model_def.args, statement)
        end
    end
    return new_model_def
end

# represent loop variables as (loop_var, lower_bound, upper_bound)
function _fully_fission_loop(
    expr, stmt_to_stmt_id, evaluation_env, current_loop=(), fissioned_stmts=[]
)
    for stmt in expr.args
        if Meta.isexpr(stmt, (:(=), :call)) # :call is for ~
            push!(fissioned_stmts, (current_loop, [stmt]))
        elseif Meta.isexpr(stmt, :for)
            MacroTools.@capture(stmt.args[1], loop_var_ = l_:h_)
            _fully_fission_loop(
                stmt.args[2],
                stmt_to_stmt_id,
                evaluation_env,
                (current_loop..., (loop_var, l, h)),
                fissioned_stmts,
            )
        end
    end
    return fissioned_stmts
end

function _sort_fissioned_stmts(stmt_dep_graph, fissioned_stmts, stmt_ids)
    sorted_stmts = Graphs.topological_sort(stmt_dep_graph)
    sorted_fissioned_stmts = []
    for stmt_id in sorted_stmts
        for (loops, stmt) in fissioned_stmts
            if stmt_ids[first(stmt)] == stmt_id
                push!(sorted_fissioned_stmts, (loops, stmt))
            end
        end
    end
    return sorted_fissioned_stmts
end

function _reconstruct_model_def_from_sorted_fissioned_stmts(sorted_fissioned_stmts)
    args = []
    for (loops, stmt) in sorted_fissioned_stmts
        if loops == ()
            push!(args, first(stmt))
        else
            push!(args, __gen_loop_expr(loops, first(stmt)))
        end
    end
    return Expr(:block, args...)
end

function __gen_loop_expr(loop_vars, stmt)
    loop_var, l, h = loop_vars[1]
    if length(loop_vars) == 1
        return MacroTools.@q for $(loop_var) in ($(l)):($(h))
            $(stmt)
        end
    else
        return MacroTools.@q for $(loop_var) in ($(l)):($(h))
            $(__gen_loop_expr(loop_vars[2:end], stmt))
        end
    end
end

function can_reorder(coarse_graph::Graphs.SimpleDiGraph)
    if Graphs.is_cyclic(coarse_graph)
        return false
    end
    return true
end

function _lower_model_def_to_represent_observe_stmts(
    reconstructed_model_def,
    stmt_to_stmt_id,
    stmt_types,
    evaluation_env,
    lowered_model_def=Expr(:block),
)
    for statement in reconstructed_model_def.args
        if Meta.isexpr(statement, (:(=), :call))
            if stmt_types[stmt_to_stmt_id[statement]] == :observed
                MacroTools.@capture(statement, lhs_ ~ rhs_)
                new_stmt = MacroTools.@q $(lhs) ≂ $(rhs)
                push!(lowered_model_def.args, new_stmt)
            else
                push!(lowered_model_def.args, statement)
            end
        elseif Meta.isexpr(statement, :for)
            # Recursively copy the inner block of the for-loop.
            new_body = _lower_model_def_to_represent_observe_stmts(
                statement.args[2], stmt_to_stmt_id, stmt_types, evaluation_env, Expr(:block)
            )
            new_for = Expr(:for, statement.args[1], new_body)
            push!(lowered_model_def.args, new_for)
        else
            # For any other kind of expression, simply include it as is.
            push!(lowered_model_def.args, statement)
        end
    end
    return lowered_model_def
end

function __variable_type(model, vn)
    if model.g[vn].is_stochastic
        if model.g[vn].is_observed
            return :observed
        else
            return :model_parameter
        end
    else
        return :deterministic
    end
end

function _stmt_type(model, var_to_stmt_id, num_stmts)
    stmt_types = fill(:unknown, num_stmts)

    for (vn, stmt_id) in var_to_stmt_id
        vt = __variable_type(model, vn)
        if stmt_types[stmt_id] == :unknown
            stmt_types[stmt_id] = vt
        elseif stmt_types[stmt_id] != vt
            error("Mixed variable types in statement: $(vn)")
        end
    end
    return stmt_types
end

## transform AST to log density computation code

function _gen_log_density_computation_function_expr(model_def, evaluation_env)
    return MacroTools.@q function __compute_log_density__(
        __evaluation_env__, __flattened_values__
    )
        (; $(keys(evaluation_env)...)) = __evaluation_env__
        __logp__ = 0.0
        __current_idx__ = 1
        $(__gen_logp_density_function_body_exprs(model_def.args, evaluation_env)...)

        @assert __current_idx__ == length(__flattened_values__) + 1
        return __logp__
    end
end

function __gen_logp_density_function_body_exprs(stmts::Vector, evaluation_env, exprs=Expr[])
    for stmt in stmts
        if Meta.isexpr(stmt, :(=))
            push!(exprs, __gen_deterministic_exprs(stmt))
        elseif Meta.isexpr(stmt, :call)
            if stmt.args[1] == :~
                push!(exprs, __gen_model_parameter_exprs(stmt).args...)
            else
                push!(exprs, __gen_observe_exprs(stmt))
            end
        else
            @assert Meta.isexpr(stmt, :for)
            new_body = __gen_logp_density_function_body_exprs(
                stmt.args[2].args, evaluation_env
            )
            new_for = Expr(:for, stmt.args[1], Expr(:block, new_body...))
            push!(exprs, new_for)
        end
    end
    return exprs
end

function __gen_observe_exprs(stmt)
    MacroTools.@capture(stmt, lhs_ ≂ rhs_)
    return MacroTools.@q __logp__ += logpdf($(rhs), $(lhs))
end

function __gen_deterministic_exprs(stmt)
    return stmt
end

function __gen_model_parameter_exprs(stmt)
    MacroTools.@capture(stmt, lhs_ ~ rhs_)
    return MacroTools.@q begin
        __dist__ = $rhs
        __b_inv__ = Bijectors.inverse(Bijectors.bijector(__dist__))
        __transformed_length__ = length(Bijectors.transformed(__dist__))
        __reconstructed_value__ = JuliaBUGS.reconstruct(
            __b_inv__,
            __dist__,
            view(
                __flattened_values__,
                (__current_idx__):(__current_idx__ + __transformed_length__ - 1),
            ),
        )
        __current_idx__ += __transformed_length__
        (__value__, __logjac__) = Bijectors.with_logabsdet_jacobian(
            __b_inv__, __reconstructed_value__
        )
        __logprior__ = Distributions.logpdf(__dist__, __value__) + __logjac__
        __logp__ = __logp__ + __logprior__
        $lhs = __value__
    end
end

## Utilities

function show_coarse_graph(
    stmt_id_to_stmt::IdDict{Int,Expr}, coarse_graph::Graphs.SimpleDiGraph
)
    for edge in Graphs.edges(coarse_graph)
        src_stmt = stmt_id_to_stmt[src(edge)]
        dst_stmt = stmt_id_to_stmt[dst(edge)]
        println("$src_stmt -> $dst_stmt")
    end
end

function _only_keep_model_parameter_stmts(lowered_model_def, new_lowered_model_def=Expr(:block))
    for statement in lowered_model_def.args
        if Meta.isexpr(statement, (:(=), :call))
            if statement.args[1] == :~
                push!(new_lowered_model_def.args, statement)
            end
        else
            @assert Meta.isexpr(statement, :for)
            new_body = _only_keep_model_parameter_stmts(
                statement.args[2], Expr(:block)
            )
            if length(new_body.args) > 0
                new_for = Expr(:for, statement.args[1], new_body)
                push!(new_lowered_model_def.args, new_for)
            end
        end
    end
    return new_lowered_model_def
end

struct CollectSortedNodes{ET} <: CompilerPass
    sorted_nodes::Vector{<:VarName}
    env::ET
end

function CollectSortedNodes(env::NamedTuple)
    return CollectSortedNodes(VarName[], env)
end

function analyze_statement(
    pass::CollectSortedNodes, expr::Expr, loop_variables::NamedTuple
)
    lhs_expression = is_deterministic(expr) ? expr.args[1] : expr.args[2]
    merged_env = merge(pass.env, loop_variables)
    simplified_lhs = simplify_lhs(merged_env, lhs_expression)
    varname = if simplified_lhs isa Symbol
        VarName{simplified_lhs}()
    else
        symbol, indices... = simplified_lhs
        VarName{symbol}(IndexLens(indices))
    end

    push!(pass.sorted_nodes, varname)
    return nothing
end
