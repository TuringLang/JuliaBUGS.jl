using BangBang
using Bijectors
using JuliaBUGS
using JuliaBUGS: _generate_lowered_model_def, _gen_log_density_computation_function_expr
using JuliaBUGS: CollectSortedNodes
using JuliaBUGS: phi # 
using JuliaBUGS.BUGSPrimitives
using LogDensityProblems
using OrderedCollections

test_examples = [
    :rats,
    :pumps,
    :dogs,
    :seeds,
    :surgical_realistic,
    # :magnesium,
    :salm,
    # :equiv, # indexing with stochastic variable of type Float64
    :dyes,
    :stacks,
    :epil,
    :blockers,
    :oxford,
    :lsat,
    # :bones, # missings in data
    # :mice, # missings in data
    # :kidney, # missings in data
    :leuk,
    :leukfr,
    :dugongs,
    :air,
    :birats,
    :schools,
]

function _create_model(model_name::Symbol)
    (; model_def, data, inits) = getfield(JuliaBUGS.BUGSExamples, model_name)
    model = compile(model_def, data, inits)
    evaluation_env = deepcopy(model.evaluation_env)
    return model, evaluation_env
end

function _create_bugsmdoel_with_consistent_sorted_nodes(
    model::JuliaBUGS.BUGSModel, reconstructed_model_def
)
    pass = CollectSortedNodes(model.evaluation_env)
    JuliaBUGS.analyze_block(pass, reconstructed_model_def)
    sorted_nodes = pass.sorted_nodes
    sorted_parameters = [vn for vn in sorted_nodes if vn in model.parameters]
    new_flattened_graph_node_data = JuliaBUGS.FlattenedGraphNodeData(model.g, sorted_nodes)
    new_model = BangBang.setproperty!!(
        model, :parameters, sorted_parameters
    )
    new_model = BangBang.setproperty!!(
        new_model, :flattened_graph_node_data, new_flattened_graph_node_data
    )
    return new_model
end

bugs_models = OrderedDict{Symbol,JuliaBUGS.BUGSModel}()
evaluation_envs = OrderedDict{Symbol,NamedTuple}()
log_density_computation_functions = OrderedDict{Symbol,Function}()
reconstructed_model_defs = OrderedDict{Symbol,Expr}()
for example_name in test_examples
    model, evaluation_env = _create_model(example_name)
    bugs_models[example_name] = model
    evaluation_envs[example_name] = evaluation_env
    lowered_model_def, reconstructed_model_def = _generate_lowered_model_def(
        model, evaluation_env
    )
    log_density_computation_expr = _gen_log_density_computation_function_expr(
        lowered_model_def, evaluation_env, gensym(example_name)
    )
    log_density_computation_functions[example_name] = eval(log_density_computation_expr)
    reconstructed_model_defs[example_name] = reconstructed_model_def
end

@testset "source_gen: $example_name" for example_name in test_examples
    model_with_consistent_sorted_nodes = _create_bugsmdoel_with_consistent_sorted_nodes(
        bugs_models[example_name], reconstructed_model_defs[example_name]
    )
    result_with_old_model = JuliaBUGS.evaluate!!(
        bugs_models[example_name]
    )[2]
    params = JuliaBUGS.getparams(model_with_consistent_sorted_nodes)
    result_with_bugsmodel = JuliaBUGS.evaluate!!(
        model_with_consistent_sorted_nodes, params
    )[2]
    result_with_log_density_computation_function = log_density_computation_functions[example_name](
        evaluation_envs[example_name], params
    )
    @test result_with_old_model ≈ result_with_bugsmodel
    @test result_with_log_density_computation_function ≈ result_with_bugsmodel
end
