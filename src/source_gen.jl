using JuliaBUGS
using MacroTools
using Graphs
using MetaGraphsNext

using JuliaBUGS:
    is_deterministic,
    simplify_lhs,
    CompilerPass,
    VarName,
    IndexLens,
    simple_arithmetic_eval,
    analyze_block
import JuliaBUGS: analyze_statement

function _assign_statement_ids(block_expr, id_map=IdDict{Expr,Int}(), next_id=1)
    for statement in block_expr.args
        if Meta.isexpr(statement, (:(=), :call))
            id_map[statement] = next_id
            next_id += 1
        elseif Meta.isexpr(statement, :for)
            next_id, id_map = _assign_statement_ids(statement.args[2], id_map, next_id)
        end
    end
    return next_id, id_map
end

struct StatementIdAttributePass <: CompilerPass
    statement_to_id::IdDict{Expr,Int}
    varname_to_statement_id::Dict{VarName,Int}
    env::NamedTuple
end

function analyze_statement(pass::StatementIdAttributePass, expr::Expr, loop_variables)
    lhs_expression = is_deterministic(expr) ? expr.args[1] : expr.args[2]
    merged_env = merge(pass.env, loop_variables)
    simplified_lhs = simplify_lhs(merged_env, lhs_expression)

    varname = if simplified_lhs isa Symbol
        VarName{simplified_lhs}()
    else
        symbol, indices... = simplified_lhs
        VarName{symbol}(IndexLens(indices))
    end

    pass.varname_to_statement_id[varname] = pass.statement_to_id[expr]
    return nothing
end

function _build_stmt_dep_graph(stmt_to_id, model, model_def)
    stmt_dep_graph = Graphs.SimpleDiGraph(length(keys(stmt_to_id)))

    pass = StatementIdAttributePass(stmt_to_id, Dict(), model.evaluation_env)
    analyze_block(pass, model_def) # TODO: use `model.model_def` can error because of IdDict, there must be a deepcopy somewhere

    # Build reverse lookup from statement ID to variable names
    id_to_varnames = Dict{Int,Vector{VarName}}()
    for (varname, stmt_id) in pass.varname_to_statement_id
        if !haskey(id_to_varnames, stmt_id)
            id_to_varnames[stmt_id] = [varname]
        else
            push!(id_to_varnames[stmt_id], varname)
        end
    end

    # Add edges based on dependencies in model graph
    for (stmt1, stmt2) in Iterators.product(1:length(stmt_to_id), 1:length(stmt_to_id))
        for (vn1, vn2) in Iterators.product(id_to_varnames[stmt1], id_to_varnames[stmt2])
            if vn2 in MetaGraphsNext.inneighbor_labels(model.g, vn1)
                Graphs.add_edge!(stmt_dep_graph, stmt2, stmt1)
            elseif vn1 in MetaGraphsNext.inneighbor_labels(model.g, vn2)
                Graphs.add_edge!(stmt_dep_graph, stmt1, stmt2)
            end
        end
    end

    return stmt_dep_graph, id_to_varnames
end

function _fission_loop(expr, stmt_ids, current_loop=(), fissioned_stmts=[])
    for stmt in expr.args
        if Meta.isexpr(stmt, (:(=), :call))
            push!(fissioned_stmts, (current_loop, stmt))
        elseif Meta.isexpr(stmt, :for)
            MacroTools.@capture(stmt.args[1], loop_var_ = l_:h_)
            l = JuliaBUGS.simple_arithmetic_eval(model.evaluation_env, l)
            h = JuliaBUGS.simple_arithmetic_eval(model.evaluation_env, h)
            _fission_loop(
                stmt.args[2], stmt_ids, (current_loop..., (loop_var, l, h)), fissioned_stmts
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
            if stmt_ids[stmt] == stmt_id
                push!(sorted_fissioned_stmts, (loops, stmt))
            end
        end
    end
    return sorted_fissioned_stmts
end

function _gen_seq_version(fissioned_stmts)
    args = []
    for (loops, stmt) in fissioned_stmts
        if loops == ()
            push!(args, stmt)
        else
            push!(args, _gen_loop_expr(loops, stmt))
        end
    end
    return Expr(:block, args...)
end

function _gen_loop_expr(loop_vars, stmt)
    loop_var, l, h = loop_vars[1]
    if length(loop_vars) == 1
        return MacroTools.@q for $(loop_var) in ($(l)):($(h))
            $(stmt)
        end
    else
        return MacroTools.@q for $(loop_var) in ($(l)):($(h))
            $(_gen_loop_expr(loop_vars[2:end], stmt))
        end
    end
end

function _build_stmt_to_type(model, stmt_ids_to_vn, stmt_ids)
    function var_type(model, vn)
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

    stmt_id_to_types = Dict()
    for (k, vns) in stmt_ids_to_vn
        vn_types = [var_type(model, vn) for vn in vns]
        if !all(==(vn_types[1]), vn_types)
            error("Mixed variable types in statement: $(vn_types)")
        end
        stmt_id_to_types[k] = vn_types[1]
    end

    stmt_to_type = IdDict()
    for (k, v) in stmt_ids
        stmt_to_type[k] = stmt_id_to_types[v]
    end

    return stmt_to_type
end

function _gen_function_expr(model_def, stmt_to_type, stmt_to_range, evaluation_env)
    return MacroTools.@q function __logp__(__evaluation_env__, __flattened_values__)
        $(_gen_NT_unpack_expr(evaluation_env))
        __logp__ = 0.0
        $(_gen_logp_eval_code(model_def, stmt_to_type, stmt_to_range, ())...)
        return __logp__
    end
end

function _gen_logp_eval_code(model_def, stmt_to_type, stmt_to_range, loop_vars)
    exs = Expr[]
    for arg in model_def.args
        if Meta.isexpr(arg, :for)
            loop_var = arg.args[1].args[1]
            l = arg.args[1].args[2].args[2]
            h = arg.args[1].args[2].args[3]
            new_loop_vars = (loop_vars..., (loop_var, (l, h)))
            push!(
                exs,
                Expr(
                    :for,
                    arg.args[1],
                    Expr(
                        :block,
                        _gen_logp_eval_code(
                            arg.args[2], stmt_to_type, stmt_to_range, new_loop_vars
                        )...,
                    ),
                ),
            )
        elseif arg in collect(keys(stmt_to_type))
            if stmt_to_type[arg] == :observed
                push!(exs, _gen_observation_expr(arg))
            elseif stmt_to_type[arg] == :model_parameter
                push!(exs, _gen_model_parameter_expr(arg, stmt_to_range, loop_vars).args...)
            else
                push!(exs, _gen_deterministic_expr(arg))
            end
        end
    end
    return exs
end

function _gen_NT_unpack_expr(evaluation_env)
    lhs = :((; $(keys(evaluation_env)...)))
    rhs = :__evaluation_env__
    return MacroTools.@q $lhs = $rhs
end

function _gen_observation_expr(expr)
    if MacroTools.@capture(expr, lhs_ ~ rhs_)
        return :(__logp__ += logpdf($rhs, $lhs))
    else
        error()
    end
end

function _gen_deterministic_expr(expr)
    if MacroTools.@capture(expr, lhs_ = rhs_)
        return expr
    else
        error()
    end
end

function _build_stmt_to_range(model, stmt_to_type, stmt_ids_to_vn, stmt_ids, sorted_stmt_ids)
    var_lengths = model.transformed_var_lengths
    stmt_id_to_range = Dict{Int,Tuple{Int,Int}}()
    current_idx = 1

    # build reverse lookup from stmt_id to stmt
    id_to_stmt = Dict{Int,Expr}()
    for (stmt, stmt_id) in stmt_ids
        id_to_stmt[stmt_id] = stmt
    end

    # the value is range and individual length
    stmt_to_range = IdDict{Expr,Tuple{Tuple{Int,Int},Int}}()

    for stmt_id in sorted_stmt_ids
        vns = stmt_ids_to_vn[stmt_id]
        stmt = id_to_stmt[stmt_id]
        if stmt_to_type[stmt] == :model_parameter
            total_length = sum(var_lengths[vn] for vn in vns)
            stmt_id_to_range[stmt_id] = (current_idx, current_idx + total_length - 1)
            stmt_to_range[stmt] = (stmt_id_to_range[stmt_id], var_lengths[vns[1]])
            current_idx += total_length
        end
    end
    return stmt_to_range, stmt_id_to_range
end

function _gen_model_parameter_expr(expr, stmt_to_range, loop_vars)
    (start_idx, end_idx), param_length = stmt_to_range[expr]
    end_idx = _gen_end_idx_expr(start_idx, loop_vars, param_length)
    if end_idx isa Expr
        if param_length == 1
            start_idx = end_idx
        else
            start_idx = :($end_idx - $(param_length - 1))
        end
    elseif end_idx isa Int
        start_idx = end_idx - param_length + 1
    else
        error()
    end
    if MacroTools.@capture(expr, lhs_ ~ rhs_)
        return MacroTools.@q begin
            __dist__ = $rhs
            __b__ = Bijectors.bijector(__dist__)
            __b_inv__ = Bijectors.inverse(__b__)
            __reconstructed_value__ = JuliaBUGS.reconstruct(
                __b_inv__, __dist__, view(__flattened_values__, ($start_idx):($end_idx))
            )
            (__value__, __logjac__) = Bijectors.with_logabsdet_jacobian(
                __b_inv__, __reconstructed_value__
            )
            __logprior__ = Distributions.logpdf(__dist__, __value__) + __logjac__
            __logp__ = __logp__ + __logprior__
            $lhs = __value__
        end
    else
        error()
    end
end

function _gen_end_idx_expr(start_idx, loop_vars, param_length)
    if isempty(loop_vars)
        return start_idx + param_length - 1
    end

    # Process loops in reverse order (inner to outer)
    reversed_loops = reverse(loop_vars)
    cumulative_product = 1  # Initial cumulative product as expression
    terms = Expr[]
    for (var, (l, h)) in reversed_loops
        size_expr = :($h - $l + 1)
        term = :(($var - $l) * $cumulative_product)
        push!(terms, term)
        cumulative_product = :($size_expr * $cumulative_product)
    end

    # Sum all terms and build final expression
    offset = length(terms) == 1 ? terms[1] : Expr(:call, :+, terms...)
    if param_length == 1
        return :($start_idx + $offset)
    else
        return :($start_idx + ($offset + 1) * $param_length - 1)
    end
end

function generate_source(model)
    model_def = model.model_def
    _, stmt_ids = _assign_statement_ids(model_def)
    stmt_dep_graph, stmt_ids_to_vn = _build_stmt_dep_graph(stmt_ids, model, model_def)
    if !isempty(Graphs.simplecycles(stmt_dep_graph))
        error("Dependency graph has cycles")
    end
    fissioned_stmts = _fission_loop(model_def, stmt_ids)
    seq_model_def = _gen_seq_version(
        _sort_fissioned_stmts(stmt_dep_graph, fissioned_stmts, stmt_ids)
    )
    stmt_to_type = _build_stmt_to_type(model, stmt_ids_to_vn, stmt_ids)
    stmt_to_range, stmt_id_to_range = _build_stmt_to_range(
        model, stmt_to_type, stmt_ids_to_vn, stmt_ids, collect(topological_sort(stmt_dep_graph))
    )
    logp_eval_code = _gen_function_expr(
        seq_model_def, stmt_to_type, stmt_to_range, model.evaluation_env
    )
    return logp_eval_code
end
