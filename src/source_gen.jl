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

function _assign_statement_ids(block_expr, id_map=IdDict{Expr,Int}(), next_id=Ref(1))
    @assert Meta.isexpr(block_expr, :block)
    for statement in block_expr.args
        if Meta.isexpr(statement, (:(=), :call))
            id_map[statement] = next_id[]
            next_id[] += 1
        elseif Meta.isexpr(statement, :for)
            id_map = _assign_statement_ids(statement.args[2], id_map, next_id)
        end
    end
    return id_map
end

struct StatementIdAttributePass <: CompilerPass
    g::JuliaBUGS.BUGSGraph
    stmt_ids::IdDict{Expr,Int}
    varname_to_stmt_id::Dict{VarName,Int}
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

    if varname in labels(pass.g)
        pass.varname_to_stmt_id[varname] = pass.stmt_ids[expr]
    end
    return nothing
end

function _build_stmt_ids_to_vns(pass)
    stmt_ids_to_vns = Dict{Int,Vector{<:VarName}}()
    for (varname, stmt_id) in pass.varname_to_stmt_id
        if !haskey(stmt_ids_to_vns, stmt_id)
            stmt_ids_to_vns[stmt_id] = [varname]
        else
            push!(stmt_ids_to_vns[stmt_id], varname)
        end
    end
    return stmt_ids_to_vns
end

function _depend_on(g, vns1, vns2)
    for vn1 in vns1
        for vn2 in vns2
            if vn2 in MetaGraphsNext.inneighbor_labels(g, vn1)
                return true
            end
        end
    end
    return false
end

function _build_stmt_dep_graph(stmt_to_id::IdDict{Expr,Int}, model)
    n_stmts = length(keys(stmt_to_id))
    stmt_dep_graph = Graphs.SimpleDiGraph(n_stmts)

    pass = StatementIdAttributePass(model.g, stmt_to_id, Dict{VarName,Int}(), model.evaluation_env)
    analyze_block(pass, model.model_def)
    stmt_ids_to_vns = _build_stmt_ids_to_vns(pass)

    for (stmt_id_1, stmt_id_2) in Iterators.product(1:n_stmts, 1:n_stmts)
        if !haskey(stmt_ids_to_vns, stmt_id_1) || !haskey(stmt_ids_to_vns, stmt_id_2)
            continue
        end
        if _depend_on(model.g, stmt_ids_to_vns[stmt_id_1], stmt_ids_to_vns[stmt_id_2])
            Graphs.add_edge!(stmt_dep_graph, stmt_id_2, stmt_id_1)
        end
    end

    return stmt_dep_graph, stmt_ids_to_vns
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

function _fuse_fissioned_stmts(fissioned_stmts)
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

function _var_type(model, vn)
    all_vns = labels(model.g)
    if !(vn in all_vns)
        return :transformed_data
    end
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

function _build_stmt_to_type(model, stmt_ids_to_vns, stmt_ids)
    stmt_id_to_types = Dict{Int,Symbol}()
    for (stmt_id, vns) in stmt_ids_to_vns
        vn_types = unique([_var_type(model, vn) for vn in vns])
        if length(vn_types) > 1
            error("Mixed variable types in statement: $(vn_types)")
        end
        stmt_id_to_types[stmt_id] = only(vn_types)
    end

    stmt_to_types = IdDict{Expr,Symbol}()
    for (stmt, stmt_id) in stmt_ids
        if !haskey(stmt_id_to_types, stmt_id)
            continue
        end
        stmt_to_types[stmt] = stmt_id_to_types[stmt_id]
    end

    return stmt_to_types
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
            if stmt_to_type[arg] == :transformed_data
                continue
            elseif stmt_to_type[arg] == :observed
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

function _build_stmt_to_range(
    model, stmt_to_types, stmt_ids_to_vns, stmt_ids, sorted_stmt_ids
)
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
        if !haskey(stmt_ids_to_vns, stmt_id)
            continue
        end
        vns = stmt_ids_to_vns[stmt_id]
        stmt = id_to_stmt[stmt_id]
        if stmt_to_types[stmt] == :model_parameter
            total_length = sum(var_lengths[vn] for vn in vns)
            stmt_id_to_range[stmt_id] = (current_idx, current_idx + total_length - 1)
            stmt_to_range[stmt] = (stmt_id_to_range[stmt_id], var_lengths[vns[1]])
            current_idx += total_length
        end
    end
    return stmt_to_range
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
    stmt_ids = _assign_statement_ids(model_def)
    stmt_dep_graph, stmt_ids_to_vn = _build_stmt_dep_graph(stmt_ids, model)
    if !isempty(Graphs.simplecycles(stmt_dep_graph))
        error("Dependency graph has cycles")
    end
    fissioned_stmts = _fission_loop(model_def, stmt_ids)
    sorted_fissioned_stmts = _sort_fissioned_stmts(stmt_dep_graph, fissioned_stmts, stmt_ids)
    fused_stmts = _fuse_fissioned_stmts(sorted_fissioned_stmts)
    stmt_to_type = _build_stmt_to_type(model, stmt_ids_to_vn, stmt_ids)
    stmt_to_range = _build_stmt_to_range(
        model,
        stmt_to_type,
        stmt_ids_to_vn,
        stmt_ids,
        collect(topological_sort(stmt_dep_graph)),
    )
    logp_eval_code = _gen_function_expr(
        fused_stmts, stmt_to_type, stmt_to_range, model.evaluation_env
    )
    return logp_eval_code
end
