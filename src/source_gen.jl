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
    all_variables_in_graph::Set{<:VarName}
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
        if haskey(pass.var_to_stmt_id, varname)
            if JuliaBUGS.is_stochastic(expr)
                # could be transformed data, so the variable should be associated with the stochastic statement
                pass.var_to_stmt_id[varname] = pass.stmt_ids[expr]
            end
        else
            pass.var_to_stmt_id[varname] = pass.stmt_ids[expr]
        end
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

function _build_stmt_id_to_var(var_to_stmt_id::Dict{VarName,Int})
    stmt_id_to_var = Dict{Int,Vector{<:VarName}}()
    for var in keys(var_to_stmt_id)
        stmt_id = var_to_stmt_id[var]
        if !haskey(stmt_id_to_var, stmt_id)
            stmt_id_to_var[stmt_id] = [var]
        else
            push!(stmt_id_to_var[stmt_id], var)
        end
    end
    return stmt_id_to_var
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

# add if statement in the lowered model def
function _lower_model_def_to_represent_observe_stmts(
    reconstructed_model_def,
    stmt_to_stmt_id,
    var_types,
    evaluation_env,
    lowered_model_def=Expr(:block),
)
    for statement in reconstructed_model_def.args
        if Meta.isexpr(statement, (:(=), :call))
            stmt_id = stmt_to_stmt_id[statement]
            observed_loop_vars, model_parameter_loop_vars, deterministic_loop_vars = var_types[stmt_id]

            _contains_observed = !isempty(observed_loop_vars)
            _contains_model_parameter = !isempty(model_parameter_loop_vars)

            if _contains_observed
                if _contains_model_parameter
                    MacroTools.@capture(statement, lhs_ ~ rhs_)
                    new_stmt = MacroTools.@q if condition_placeholder
                        $(lhs) ~ $(rhs)
                    else
                        $(lhs) ≂ $(rhs)
                    end
                    new_stmt.args[1] = __generate_model_parameter_condition_expr(
                        model_parameter_loop_vars
                    )
                    push!(lowered_model_def.args, new_stmt)
                else
                    MacroTools.@capture(statement, lhs_ ~ rhs_)
                    new_stmt = MacroTools.@q $(lhs) ≂ $(rhs)
                    push!(lowered_model_def.args, new_stmt)
                end
            else
                push!(lowered_model_def.args, statement)
            end
        elseif Meta.isexpr(statement, :for)
            # Recursively copy the inner block of the for-loop.
            new_body = _lower_model_def_to_represent_observe_stmts(
                statement.args[2], stmt_to_stmt_id, var_types, evaluation_env, Expr(:block)
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

function __generate_model_parameter_condition_expr(model_param_nt_vec)
    guard_exprs = []
    for nt in model_param_nt_vec
        condition_parts = []
        for (field, val) in pairs(nt)
            push!(condition_parts, MacroTools.@q($(field) == $(val)))
        end
        if length(condition_parts) > 1
            condition = Expr(:&&, condition_parts...)
        elseif length(condition_parts) == 1
            condition = condition_parts[1]
        else
            continue
        end

        push!(guard_exprs, condition)
    end

    if isempty(guard_exprs)
        return false
    elseif length(guard_exprs) == 1
        return guard_exprs[1]
    else
        # Need to nest the || expressions to match the expected AST structure
        result = guard_exprs[end]
        for i in (length(guard_exprs) - 1):-1:1
            result = Expr(:||, guard_exprs[i], result)
        end
        return result
    end
end

function _generate_lowered_model_def(model, evaluation_env)
    stmt_to_stmt_id = _build_stmt_to_stmt_id(model.model_def)
    stmt_id_to_stmt = _build_stmt_id_to_stmt(stmt_to_stmt_id)
    var_to_stmt_id = _build_var_to_stmt_id(model, stmt_to_stmt_id)
    stmt_id_to_var = _build_stmt_id_to_var(var_to_stmt_id)
    coarse_graph = _build_coarse_dep_graph(model, stmt_to_stmt_id, var_to_stmt_id)
    # show_coarse_graph(stmt_id_to_stmt, coarse_graph)
    model_def_removed_transformed_data = _copy_and_remove_stmt_with_degree_0(
        model.model_def, stmt_to_stmt_id, coarse_graph
    )
    fissioned_stmts = _fully_fission_loop(
        model_def_removed_transformed_data, stmt_to_stmt_id, evaluation_env
    )
    sorted_fissioned_stmts = _sort_fissioned_stmts(
        coarse_graph, fissioned_stmts, stmt_to_stmt_id
    )
    reconstructed_model_def = _reconstruct_model_def_from_sorted_fissioned_stmts(
        sorted_fissioned_stmts
    )
    induction_variable_values = _var_to_loop_vars(model, evaluation_env)
    var_types = __determine_var_types(
        model, stmt_id_to_var, stmt_id_to_stmt, induction_variable_values
    )
    lowered_model_def = _lower_model_def_to_represent_observe_stmts(
        reconstructed_model_def, stmt_to_stmt_id, var_types, evaluation_env
    )
    return __cast_array_indices_to_Int(
        __qualify_builtins_with_JuliaBUGS_namespace(lowered_model_def)
    ),
    reconstructed_model_def
end

function __cast_array_indices_to_Int(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, v_[indices__])
            new_indices = Any[]
            for index in indices
                if index isa Int
                    push!(new_indices, index)
                elseif index isa Symbol || Meta.isexpr(index, :ref) # cast to Int if it's a variable
                    push!(new_indices, Expr(:call, :Int, index))
                else # function and range are not casted
                    push!(new_indices, index)
                end
            end
            return Expr(:ref, v, new_indices...)
        end
        return sub_expr
    end
end

function __qualify_builtins_with_JuliaBUGS_namespace(expr)
    function_names = (:phi,)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, func_(args__))
            if func in function_names
                return MacroTools.@q(JuliaBUGS.$func($(args...)))
            end
        end
        return sub_expr
    end
end

struct CollectLoopInductionVariableValues{ET} <: CompilerPass
    env::ET
    induction_variable_values::Dict{VarName,NamedTuple}
end

function CollectLoopInductionVariableValues(env::NamedTuple)
    return CollectLoopInductionVariableValues(env, Dict{VarName,NamedTuple}())
end

function analyze_statement(
    pass::CollectLoopInductionVariableValues, expr::Expr, loop_variables::NamedTuple
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
    return pass.induction_variable_values[varname] = loop_variables
end

function _var_to_loop_vars(model, evaluation_env)
    pass = CollectLoopInductionVariableValues(evaluation_env)
    analyze_block(pass, model.model_def)
    return pass.induction_variable_values
end

function __determine_var_types(
    model, stmt_id_to_var, stmt_id_to_stmt, induction_variable_values
)
    # for each statement, have three list to collect the var of each type
    var_types = [([], [], []) for _ in 1:length(stmt_id_to_stmt)]
    for stmt_id in keys(stmt_id_to_stmt)
        if !haskey(stmt_id_to_var, stmt_id)
            continue
        end
        vars = stmt_id_to_var[stmt_id]
        for var in vars
            var_type = __variable_type(model, var)
            if var_type == :observed
                push!(var_types[stmt_id][1], induction_variable_values[var])
            elseif var_type == :model_parameter
                push!(var_types[stmt_id][2], induction_variable_values[var])
            else
                push!(var_types[stmt_id][3], induction_variable_values[var])
            end
        end
    end
    return var_types
end

function __variable_type(model, var)
    if model.g[var].is_stochastic
        if model.g[var].is_observed
            return :observed
        else
            return :model_parameter
        end
    else
        return :deterministic
    end
end

## transform AST to log density computation code

function _gen_log_density_computation_function_expr(
    model_def, evaluation_env, function_name::Symbol=:__compute_log_density__
)
    return MacroTools.@q function $function_name(__evaluation_env__, __flattened_values__)
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
        elseif Meta.isexpr(stmt, :for)
            new_body = __gen_logp_density_function_body_exprs(
                stmt.args[2].args, evaluation_env
            )
            new_for = Expr(:for, stmt.args[1], Expr(:block, new_body...))
            push!(exprs, new_for)
        elseif Meta.isexpr(stmt, :if)
            new_if = _handle_if_expr(stmt, evaluation_env)
            push!(exprs, new_if)
        else
            error("Unsupported statement: $stmt")
        end
    end
    return exprs
end

function _handle_if_expr(stmt, evaluation_env)
    # stmt.args[1] = if-condition
    # stmt.args[2] = block for condition == true
    # stmt.args[3] = "else" branch which might itself be an :if (for elseif) or a block (for else)
    cond_expr = stmt.args[1]
    then_expr = stmt.args[2]
    else_expr = length(stmt.args) == 3 ? stmt.args[3] : nothing

    # Recursively lower the "then" block
    new_then_body = __gen_logp_density_function_body_exprs(then_expr.args, evaluation_env)
    new_then_block = Expr(:block, new_then_body...)

    # Recursively handle the "else" side, which could be nested if/elseif
    new_else_block = _handle_else_expr(else_expr, evaluation_env)

    return Expr(:if, cond_expr, new_then_block, new_else_block)
end

function _handle_else_expr(expr, evaluation_env)
    if expr === nothing
        # no else branch at all
        return nothing
    elseif Meta.isexpr(expr, :if)
        # means we have an 'elseif' situation
        return _handle_if_expr(expr, evaluation_env)
    elseif Meta.isexpr(expr, :block)
        # just an else block with statements
        new_else_body = __gen_logp_density_function_body_exprs(expr.args, evaluation_env)
        return Expr(:block, new_else_body...)
    else
        # single-statement else (rare, but possible)
        return expr
    end
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
        __b__ = Bijectors.bijector(__dist__)
        __b_inv__ = Bijectors.inverse(__b__)
        __transformed_length__ = if __b__ === identity
            length(__dist__)
        else
            length(Bijectors.transformed(__dist__, __b__))
        end
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

struct CollectSortedNodes{ET} <: CompilerPass
    sorted_nodes::Vector{<:VarName}
    env::ET
end

function CollectSortedNodes(env::NamedTuple)
    return CollectSortedNodes(VarName[], env)
end

function analyze_statement(pass::CollectSortedNodes, expr::Expr, loop_variables::NamedTuple)
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
