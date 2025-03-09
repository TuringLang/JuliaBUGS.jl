using JuliaBUGS
using JuliaBUGS: _generate_lowered_model_def, _gen_log_density_computation_function_expr
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS: phi
using BangBang
using Bijectors
using LogDensityProblems

##

# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.pumps # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.dogs # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.seeds # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.surgical_realistic # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.magnesium # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.salm # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.equiv # ✗, indexing with stochastic variable of type Float64
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.dyes # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.stacks # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.epil # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.blockers # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.oxford # ✓
(; model_def, data, inits) = JuliaBUGS.BUGSExamples.lsat # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.bones # ✗, missings in data
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.mice # ✗, missings in data
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.kidney # ✗, missings in data
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.leuk # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.leukfr # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.dugongs # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.air # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.birats # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.schools # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.beetles # ✓
# (; model_def, data, inits) = JuliaBUGS.BUGSExamples.alligators # ✓

model = compile(model_def, data, inits)
evaluation_env = deepcopy(model.evaluation_env)

##

lowered_model_def = _generate_lowered_model_def(model, evaluation_env)
log_density_computation_expr = _gen_log_density_computation_function_expr(
    lowered_model_def, evaluation_env
)

eval(log_density_computation_expr)

## test against old implementation
using JuliaBUGS: CollectSortedNodes

pass = CollectSortedNodes(evaluation_env)
JuliaBUGS.analyze_block(pass, reconstructed_model_def)
sorted_nodes = pass.sorted_nodes
new_flattened_graph_node_data = JuliaBUGS.FlattenedGraphNodeData(model.g, sorted_nodes)
new_model = BangBang.setproperty!!(
    model, :flattened_graph_node_data, new_flattened_graph_node_data
)
params = JuliaBUGS.getparams(new_model)

__compute_log_density__(evaluation_env, params)
JuliaBUGS.evaluate!!(new_model, params)[2]

__compute_log_density__(evaluation_env, params) ≈ JuliaBUGS.evaluate!!(new_model, params)[2]

##

using DifferentiationInterface, Mooncake, Enzyme
using BenchmarkTools: @benchmark

logp = Base.Fix1(__compute_log_density__, evaluation_env)
backend = AutoMooncake(; config=nothing)
backend = AutoEnzyme()
p = rand(LogDensityProblems.dimension(model))
prep = prepare_gradient(logp, backend, p)
@benchmark logp($p)
@benchmark gradient($logp, $prep, $backend, $p)

@benchmark __compute_log_density__($evaluation_env, $p)
@profview for i in 1:1_000
    __compute_log_density__(evaluation_env, p)
end

@profview_allocs for i in 1:100_000
    gradient(logp, prep, backend, p)
end

@profview for i in 1:100000
    gradient(logp, prep, backend, p)
end

using DifferentiationInterface: Constant
backend = AutoEnzyme()
f(p, env) = __compute_log_density__(env, p)
enzyme_prep = prepare_gradient(f, backend, p, Constant(evaluation_env))
@benchmark gradient(f, $enzyme_prep, $backend, $p, $(Constant(evaluation_env)))
gradient(f, enzyme_prep, backend, p, Constant(evaluation_env))

moon_backend = AutoMooncake(; config=nothing)
moon_prep = prepare_gradient(f, moon_backend, p, Constant(evaluation_env))
@benchmark gradient(f, $moon_prep, $moon_backend, $p, $(Constant(evaluation_env)))
gradient(f, moon_prep, moon_backend, p, Constant(evaluation_env))

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
