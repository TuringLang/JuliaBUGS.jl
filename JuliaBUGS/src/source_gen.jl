# For more background and descriptions, see /docs/src/source_gen.md
# the external facing function in this file is `_generate_lowered_model_def`, so start their first
# the utils section have couple of helper functions that might be useful for debugging

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

function _build_var_to_stmt_id(
    model_def::Expr,
    g::JuliaBUGS.BUGSGraph,
    evaluation_env::NamedTuple,
    stmt_ids::IdDict{Expr,Int},
)
    pass = StatementIdAttributePass(
        Set{VarName}(labels(g)), stmt_ids, evaluation_env, Dict{VarName,Int}()
    )
    analyze_block(pass, model_def)
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

# coarse graph may contains nodes whose degrees are 0, these are transformed data
function _build_coarse_dep_graph(
    g::JuliaBUGS.BUGSGraph,
    stmt_to_stmt_id::IdDict{Expr,Int},
    var_to_stmt_id::Dict{VarName,Int},
)
    # there is a node in the coarse graph for each statement in the model
    coarse_graph = Graphs.SimpleDiGraph(length(stmt_to_stmt_id))

    # this is the same as merging the nodes in the original graph
    for edge in Graphs.edges(g.graph)
        src_varname = label_for(g, src(edge))
        dst_varname = label_for(g, dst(edge))
        src_stmt_id = var_to_stmt_id[src_varname]
        dst_stmt_id = var_to_stmt_id[dst_varname]
        add_edge!(coarse_graph, src_stmt_id, dst_stmt_id)
    end
    return coarse_graph
end

# the purpose of removing nodes with degree 0 is to remove transformed data
function _copy_and_remove_stmt_with_degree_0(
    model_def, stmt_to_stmt_id, coarse_graph, new_model_def=Expr(:block)
)
    @assert Meta.isexpr(model_def, :block)
    for statement in model_def.args
        if Meta.isexpr(statement, :(=))
            # this is to remove transformed data statements
            if degree(coarse_graph, stmt_to_stmt_id[statement]) != 0
                push!(new_model_def.args, statement)
            end
        elseif Meta.isexpr(statement, (:(=), :call))
            # even if a stochastic statement has degree 0, it should be included
            # because it is part of the model
            push!(new_model_def.args, statement)
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
    args = Any[]

    i = 1
    N = length(sorted_fissioned_stmts)
    while i <= N
        loops_i, stmti = sorted_fissioned_stmts[i]
        # collect consecutive statements with identical loop nests
        group_stmts = Any[]
        j = i
        while j <= N
            loops_j, stmtj = sorted_fissioned_stmts[j]
            if loops_j == loops_i
                append!(group_stmts, stmtj)
                j += 1
            else
                break
            end
        end

        if loops_i == ()
            # top-level sequential statements
            append!(args, group_stmts)
        else
            push!(args, __gen_loop_expr(loops_i, group_stmts))
        end
        i = j
    end

    return Expr(:block, args...)
end

# Overload to generate nested loops around a block of statements
function __gen_loop_expr(loop_vars, stmts::Vector)
    loop_var, l, h = loop_vars[1]
    if length(loop_vars) == 1
        return MacroTools.@q for $(loop_var) in ($(l)):($(h))
            $(Expr(:block, stmts...))
        end
    else
        return MacroTools.@q for $(loop_var) in ($(l)):($(h))
            $(__gen_loop_expr(loop_vars[2:end], stmts))
        end
    end
end

# Backward-compatible helper to handle single statement
function __gen_loop_expr(loop_vars, stmt)
    return __gen_loop_expr(loop_vars, Any[stmt])
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

function __check_for_reserved_names(model_def::Expr)
    variable_names_and_numdims = JuliaBUGS.extract_variable_names_and_numdims(model_def)
    variable_names = keys(variable_names_and_numdims)
    bad_variable_names = filter(
        variable_name ->
            startswith(string(variable_name), "__") &&
                endswith(string(variable_name), "__"),
        variable_names,
    )
    if !isempty(bad_variable_names)
        error(
            "Variable names starting and ending with double underscores (like `__logp__`) are reserved for internal use. " *
            "Found the following reserved variable names in your model:\n" *
            "`$(join(bad_variable_names, "`, `"))`\n" *
            "Please rename these variables to avoid conflicts with internal functionality.",
        )
    end
    return nothing
end

function _generate_lowered_model_def(
    model_def::Expr,
    g::JuliaBUGS.BUGSGraph,
    evaluation_env::NamedTuple;
    diagnostics::Vector{String}=String[],
)
    __check_for_reserved_names(model_def)
    stmt_to_stmt_id = _build_stmt_to_stmt_id(model_def)
    stmt_id_to_stmt = _build_stmt_id_to_stmt(stmt_to_stmt_id)
    var_to_stmt_id = _build_var_to_stmt_id(model_def, g, evaluation_env, stmt_to_stmt_id)
    stmt_id_to_var = _build_stmt_id_to_var(var_to_stmt_id)
    coarse_graph = _build_coarse_dep_graph(g, stmt_to_stmt_id, var_to_stmt_id)
    # Remove transformed data before fissioning
    model_def_removed_transformed_data = _copy_and_remove_stmt_with_degree_0(
        model_def, stmt_to_stmt_id, coarse_graph
    )
    # Fully fission now so we can reason about each statement's loop nest
    fissioned_stmts = _fully_fission_loop(
        model_def_removed_transformed_data, stmt_to_stmt_id, evaluation_env
    )
    # If there are cycles at the coarse statement level, try to resolve them
    # by analyzing fine-grained dependence vectors. If all cycles are
    # loop-carried with lexicographically non-negative distances within
    # the same loop nest, they are sequentially valid and we can either
    # drop those edges (self or cross-statement) or fuse statements into
    # a single loop with per-iteration ordering.
    ordering_graph, ok = _build_ordering_graph_via_dependence_vectors(
        g, coarse_graph, var_to_stmt_id; diagnostics=diagnostics
    )
    sorted_fissioned_stmts = nothing
    if !ok || Graphs.is_cyclic(ordering_graph)
        # Try to resolve remaining cycles by loop fusion within identical loop nests.
        stmt_order = _attempt_resolve_cycles_via_loop_fusion(
            g,
            ordering_graph,
            var_to_stmt_id,
            fissioned_stmts,
            stmt_to_stmt_id;
            diagnostics=diagnostics,
        )
        if stmt_order === nothing
            if !isempty(diagnostics)
                @warn "Source generation aborted due to unsafe/corner-case dependencies\n - $(join(diagnostics, "\n - "))"
            end
            return nothing, nothing
        end
        sorted_fissioned_stmts = _sort_fissioned_stmts_by_stmt_order(
            stmt_order, fissioned_stmts, stmt_to_stmt_id
        )
    else
        # Use the filtered ordering graph (with loop-carried non-negative
        # dependences removed) to sort fissioned statements.
        sorted_fissioned_stmts = _sort_fissioned_stmts(
            ordering_graph, fissioned_stmts, stmt_to_stmt_id
        )
    end
    reconstructed_model_def = _reconstruct_model_def_from_sorted_fissioned_stmts(
        sorted_fissioned_stmts
    )
    induction_variable_values = _var_to_loop_vars(model_def, evaluation_env)
    var_types = __determine_var_types(
        g, stmt_id_to_var, stmt_id_to_stmt, induction_variable_values
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

function _var_to_loop_vars(model_def, evaluation_env)
    pass = CollectLoopInductionVariableValues(evaluation_env)
    analyze_block(pass, model_def)
    return pass.induction_variable_values
end

function __determine_var_types(
    g::JuliaBUGS.BUGSGraph, stmt_id_to_var, stmt_id_to_stmt, induction_variable_values
)
    # for each statement, have three list to collect the var of each type
    var_types = [([], [], []) for _ in 1:length(stmt_id_to_stmt)]
    for stmt_id in keys(stmt_id_to_stmt)
        if !haskey(stmt_id_to_var, stmt_id)
            continue
        end
        vars = stmt_id_to_var[stmt_id]
        for var in vars
            var_type = __variable_type(g, var)
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

function __variable_type(g::JuliaBUGS.BUGSGraph, var)
    if g[var].is_stochastic
        if g[var].is_observed
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
        elseif Meta.isexpr(stmt, :block)
            # Flatten nested blocks (e.g., grouped statements inside loop bodies)
            new_inner = __gen_logp_density_function_body_exprs(stmt.args, evaluation_env)
            append!(exprs, new_inner)
        else
            error("Unsupported statement: $stmt")
        end
    end
    return exprs
end

function _handle_if_expr(stmt, evaluation_env)
    cond_expr = stmt.args[1]
    then_expr = stmt.args[2]
    elseif_or_else_expr = length(stmt.args) == 3 ? stmt.args[3] : nothing

    new_then_body = __gen_logp_density_function_body_exprs(then_expr.args, evaluation_env)
    new_then_block = Expr(:block, new_then_body...)
    new_else_block = _handle_else_expr(elseif_or_else_expr, evaluation_env)
    return Expr(:if, cond_expr, new_then_block, new_else_block)
end

function _handle_else_expr(expr, evaluation_env)
    if expr === nothing # no else clause 
        return nothing
    elseif Meta.isexpr(expr, :elseif)
        return _handle_if_expr(expr, evaluation_env)
    elseif Meta.isexpr(expr, :block) # else
        new_else_body = __gen_logp_density_function_body_exprs(expr.args, evaluation_env)
        return Expr(:block, new_else_body...)
    else
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
        __reconstructed_value__ = JuliaBUGS.Model.reconstruct(
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

# first call `Graphs.simplecycles(coarse_graph)` to find the cycles in the coarse graph
# then call this function to find the corresponding fine-grained edges
function _find_corresponding_fine_grained_edges(
    g::JuliaBUGS.BUGSGraph,
    var_to_stmt_id::Dict{VarName,Int},
    src_stmt_id::Int,
    dst_stmt_id::Int,
)
    # Find all fine-grained edges that correspond to the coarse edge (src_stmt_id, dst_stmt_id)
    fine_grained_edges = []

    for edge in Graphs.edges(g.graph)
        src_varname = MetaGraphsNext.label_for(g, src(edge))
        dst_varname = MetaGraphsNext.label_for(g, dst(edge))

        # Check if this fine-grained edge maps to the coarse edge we're looking for
        if var_to_stmt_id[src_varname] == src_stmt_id &&
            var_to_stmt_id[dst_varname] == dst_stmt_id
            push!(fine_grained_edges, (src_varname, dst_varname))
        end
    end

    return fine_grained_edges
end

# Determine the lexicographic relation between two iteration vectors (loop vars).
# Returns:
# - :zero       -> loop-independent dependence (same iteration)
# - :positive   -> loop-carried with lexicographically non-negative (and not all zero)
# - :negative   -> lexicographically negative (invalid for sequential order)
# - :unknown    -> cannot compare (different loop nests or empty)
function _lex_dependence_relation(src_lv::NamedTuple, dst_lv::NamedTuple)
    # Require identical loop nests (same keys in the same order)
    src_keys = Tuple(keys(src_lv))
    dst_keys = Tuple(keys(dst_lv))
    if src_keys != dst_keys
        return :unknown
    end
    if length(src_keys) == 0
        return :unknown
    end

    # Compute difference vector dst - src in lexicographic order
    first_nonzero = 0
    for k in src_keys
        d = Int(getfield(dst_lv, k)) - Int(getfield(src_lv, k))
        if d != 0
            first_nonzero = d
            break
        end
    end
    if first_nonzero == 0
        return :zero
    elseif first_nonzero > 0
        return :positive
    else
        return :negative
    end
end

# Classify a fine-grained edge by its dependence vector category
function _classify_fine_edge(g::JuliaBUGS.BUGSGraph, src_vn::VarName, dst_vn::VarName)
    src_lv = g[src_vn].loop_vars
    dst_lv = g[dst_vn].loop_vars
    rel = _lex_dependence_relation(src_lv, dst_lv)
    return rel
end

# Build an ordering graph for statements by removing edges that are purely
# loop-carried with lexicographically non-negative dependence vectors. If any
# edge has a lexicographically negative dependence, the graph is invalid.
# IMPORTANT: Only removes positive edges for self-dependencies to avoid unsafe reorderings.
function _build_ordering_graph_via_dependence_vectors(
    g::JuliaBUGS.BUGSGraph,
    coarse_graph::Graphs.SimpleDiGraph,
    var_to_stmt_id::Dict{VarName,Int};
    diagnostics::Vector{String}=String[],
)
    ordering_graph = Graphs.SimpleDiGraph(Graphs.nv(coarse_graph))

    # Iterate all coarse edges and decide whether to keep them for ordering
    for e in Graphs.edges(coarse_graph)
        src_stmt_id = Graphs.src(e)
        dst_stmt_id = Graphs.dst(e)
        fine_edges = _find_corresponding_fine_grained_edges(
            g, var_to_stmt_id, src_stmt_id, dst_stmt_id
        )

        # If we can't find the fine edges, be conservative: keep the edge.
        if isempty(fine_edges)
            Graphs.add_edge!(ordering_graph, src_stmt_id, dst_stmt_id)
            continue
        end

        # Check all fine edges to classify the coarse edge
        all_positive = true
        for (src_vn, dst_vn) in fine_edges
            rel = _classify_fine_edge(g, src_vn, dst_vn)
            if rel === :negative
                push!(
                    diagnostics,
                    "Negative dependence prevents ordering: $(src_stmt_id) -> $(dst_stmt_id) via $(src_vn) -> $(dst_vn)",
                )
                return ordering_graph, false
            elseif rel === :unknown
                push!(
                    diagnostics,
                    "Unknown dependence (different loop nests or missing info): $(src_stmt_id) -> $(dst_stmt_id) via $(src_vn) -> $(dst_vn)",
                )
            end
            if rel !== :positive
                all_positive = false
            end
        end

        # Decision logic based on whether it's a self-edge or cross-statement edge
        if src_stmt_id == dst_stmt_id
            # Self-edge: only drop if ALL fine edges are positive (loop-carried)
            # This safely breaks recursion cycles like x[t] ~ f(x[t-1])
            if !all_positive
                Graphs.add_edge!(ordering_graph, src_stmt_id, dst_stmt_id)
            end
        else
            # Cross-statement edge: keep by default; it may later be relaxed if
            # the component can be safely fused by _attempt_resolve_cycles_via_loop_fusion.
            Graphs.add_edge!(ordering_graph, src_stmt_id, dst_stmt_id)
        end
    end

    return ordering_graph, true
end

# Build a mapping from statement id to its fissioned loop nest (tuple of (var, lb, ub)).
function _build_stmt_to_loops_map(fissioned_stmts, stmt_ids)
    stmt_to_loops = Dict{Int,Any}()
    for (loops, stmt) in fissioned_stmts
        sid = stmt_ids[first(stmt)]
        stmt_to_loops[sid] = loops
    end
    return stmt_to_loops
end

_loop_var_names(loops) = map(lvh -> lvh[1], collect(loops))

# Attempt to resolve cycles by fusing statements that:
# - are in the same SCC
# - share identical loop variable names and identical bounds (same loop nest)
# - have no lexicographically negative fine-grained dependences among them
# Ordering inside the fused loop is determined by zero-dependence edges.
# Returns a vector of statement ids in a globally valid order, or nothing if not possible.
function _attempt_resolve_cycles_via_loop_fusion(
    g::JuliaBUGS.BUGSGraph,
    ordering_graph::Graphs.SimpleDiGraph,
    var_to_stmt_id::Dict{VarName,Int},
    fissioned_stmts,
    stmt_ids::IdDict{Expr,Int};
    diagnostics::Vector{String}=String[],
)
    stmt_to_loops = _build_stmt_to_loops_map(fissioned_stmts, stmt_ids)

    # Identify SCCs
    sccs = Graphs.strongly_connected_components(ordering_graph)

    # Track which SCCs we will fuse and their internal orders
    fuseable = Dict{Int,Vector{Int}}() # scc_index => ordered stmt ids inside SCC

    for (scc_idx, nodes) in enumerate(sccs)
        if length(nodes) <= 1
            continue
        end

        # Require all statements in SCC to have identical loop nests (names and bounds)
        loops_first = get(stmt_to_loops, nodes[1], nothing)
        if loops_first === nothing
            push!(diagnostics, "Cannot fuse SCC $(scc_idx): missing loop nest metadata")
            return nothing
        end
        names_first = _loop_var_names(loops_first)
        same_loops = true
        for n in nodes[2:end]
            loops_n = get(stmt_to_loops, n, nothing)
            if loops_n === nothing
                push!(
                    diagnostics,
                    "Cannot fuse SCC $(scc_idx): missing loop nest metadata for statement $(n)",
                )
                return nothing
            end
            if _loop_var_names(loops_n) != names_first || loops_n != loops_first
                same_loops = false
                break
            end
        end
        if !same_loops
            push!(
                diagnostics,
                "Cannot fuse SCC $(scc_idx): statements have different loop nests",
            )
            return nothing
        end

        # Build a subgraph with edges only for zero-dependence (loop-independent) relations
        zero_graph = Graphs.SimpleDiGraph(length(nodes))
        idx_of = Dict(n => i for (i, n) in enumerate(nodes))

        # Check all fine edges among nodes for negativity/unknown; collect zero edges
        for u in nodes, v in nodes
            if u == v
                continue
            end
            # find all fine-grained edges mapping u->v
            fine_edges = _find_corresponding_fine_grained_edges(g, var_to_stmt_id, u, v)
            if isempty(fine_edges)
                continue
            end
            # classify
            has_zero = false
            for (src_vn, dst_vn) in fine_edges
                rel = _classify_fine_edge(g, src_vn, dst_vn)
                if rel === :negative
                    push!(
                        diagnostics,
                        "Cannot fuse SCC $(scc_idx): negative dependence inside SCC ($(u) -> $(v))",
                    )
                    return nothing
                elseif rel === :unknown
                    # Edges across different loop nests or missing loop info
                    # make this SCC unsafe to fuse; abort.
                    push!(
                        diagnostics,
                        "Cannot fuse SCC $(scc_idx): unknown dependence inside SCC ($(u) -> $(v))",
                    )
                    return nothing
                elseif rel === :zero
                    has_zero = true
                end
            end
            if has_zero
                Graphs.add_edge!(zero_graph, idx_of[u], idx_of[v])
            end
        end

        # zero_graph must be acyclic to yield an intra-iteration order
        if Graphs.is_cyclic(zero_graph)
            push!(
                diagnostics,
                "Cannot fuse SCC $(scc_idx): intra-iteration order (zero-dep edges) is cyclic",
            )
            return nothing
        end
        local_order = [nodes[i] for i in Graphs.topological_sort(zero_graph)]
        # If zero_graph has no edges, keep original node order as a fallback
        if isempty(local_order)
            local_order = copy(nodes)
        end
        fuseable[scc_idx] = local_order
    end

    # If there are cycles but none were fuseable, abort
    any_fused = any(length(v) > 1 for v in values(fuseable))
    if !any_fused
        push!(diagnostics, "No fuseable SCCs found; cycles remain")
        return nothing
    end

    # Build a condensed cluster graph: each SCC becomes a cluster; for fuseable SCCs
    # we will drop internal edges and expand in the computed local order later.
    cluster_graph = Graphs.SimpleDiGraph(length(sccs))
    # Map stmt -> cluster index
    stmt_to_cluster = Dict{Int,Int}()
    for (ci, ns) in enumerate(sccs)
        for n in ns
            stmt_to_cluster[n] = ci
        end
    end
    # Add inter-cluster edges
    for e in Graphs.edges(ordering_graph)
        cu = stmt_to_cluster[Graphs.src(e)]
        cv = stmt_to_cluster[Graphs.dst(e)]
        if cu != cv
            Graphs.add_edge!(cluster_graph, cu, cv)
        end
    end

    # Topologically sort clusters
    cluster_order = Graphs.topological_sort(cluster_graph)
    # Expand clusters into a flat statement order
    stmt_order = Int[]
    for cid in cluster_order
        nodes = sccs[cid]
        if haskey(fuseable, cid)
            append!(stmt_order, fuseable[cid])
        else
            # size-1 SCC or non-fuseable SCC (should not exist here if cycles remain)
            append!(stmt_order, nodes)
        end
    end
    return stmt_order
end

# Sort fissioned statements according to an explicit statement id order
function _sort_fissioned_stmts_by_stmt_order(
    stmt_order::Vector{Int}, fissioned_stmts, stmt_ids
)
    order_pos = Dict{Int,Int}(sid => i for (i, sid) in enumerate(stmt_order))
    # Filter only statements that appear in order (some transformed-data removed ones may be absent)
    items = []
    for (loops, stmt) in fissioned_stmts
        sid = stmt_ids[first(stmt)]
        if haskey(order_pos, sid)
            push!(items, (order_pos[sid], loops, stmt))
        end
    end
    sort!(items; by=x -> x[1])
    return [(loops, stmt) for (_, loops, stmt) in items]
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
