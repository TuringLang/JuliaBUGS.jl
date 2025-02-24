using JuliaBUGS
using JuliaBUGS:
    _build_stmt_to_stmt_id,
    _build_stmt_id_to_stmt,
    _build_var_to_stmt_id,
    _build_coarse_dep_graph,
    show_coarse_graph,
    _fully_fission_loop,
    _copy_and_remove_stmt_with_degree_0,
    _sort_fissioned_stmts,
    _reconstruct_model_def_from_sorted_fissioned_stmts,
    _lower_model_def_to_represent_observe_stmts,
    _stmt_type,
    _gen_log_density_computation_function_expr
using JuliaBUGS.BUGSPrimitives
using Bijectors
using LogDensityProblems

# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.dogs
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.salm
(; model_def, data, inits) = JuliaBUGS.BUGSExamples.lsat
model = compile(model_def, data, inits)
rand_params = rand(65)
inits_params = JuliaBUGS.getparams(model)
evaluation_env = deepcopy(model.evaluation_env)

##

stmt_to_stmt_id = _build_stmt_to_stmt_id(model.model_def)
stmt_id_to_stmt = _build_stmt_id_to_stmt(stmt_to_stmt_id)
var_to_stmt_id = _build_var_to_stmt_id(model, stmt_to_stmt_id)
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

stmt_types = _stmt_type(model, var_to_stmt_id, length(stmt_to_stmt_id))

lowered_model_def = _lower_model_def_to_represent_observe_stmts(
    reconstructed_model_def, stmt_to_stmt_id, stmt_types, evaluation_env
)

log_density_computation_expr = _gen_log_density_computation_function_expr(
    lowered_model_def, evaluation_env
)

eval(log_density_computation_expr)
D = LogDensityProblems.dimension(model)
p = fill(rand(), D) # is this reliable? 
__compute_log_density__(evaluation_env, p)
JuliaBUGS.evaluate!!(model, p)[2]

##
using JuliaBUGS: _only_keep_model_parameter_stmts, CollectSortedNodes
# TODO: did I preserve the skipping when lower bound is higher than upper bound?
model_parameter_only_model_def = _only_keep_model_parameter_stmts(lowered_model_def)

pass = CollectSortedNodes(evaluation_env)
JuliaBUGS.analyze_block(pass, model_parameter_only_model_def)
sorted_nodes = pass.sorted_nodes
using BangBang
new_flattened_graph_node_data = JuliaBUGS.FlattenedGraphNodeData(
    model.g, sorted_nodes
)
new_model = BangBang.@set!! model.flattened_graph_node_data = new_flattened_graph_node_data
params = JuliaBUGS.getparams(new_model)

__compute_log_density__(evaluation_env, params)
JuliaBUGS.evaluate!!(new_model, params)[2]

using DifferentiationInterface, Mooncake
using BenchmarkTools: @benchmark

logp = Base.Fix1(__compute_log_density__, evaluation_env)
backend = AutoMooncake(; config=nothing)
prep = prepare_gradient(logp, backend, p)
@benchmark gradient($logp, $prep, $backend, $p)
@benchmark logp($p)

@benchmark __compute_log_density__($evaluation_env, $p)

@benchmark JuliaBUGS.evaluate!!($new_model, $params)

##

