using BangBang
using Bijectors
using JuliaBUGS
using JuliaBUGS: _generate_lowered_model_def, _gen_log_density_computation_function_expr
using JuliaBUGS: CollectSortedNodes
using JuliaBUGS.BUGSPrimitives
using LogDensityProblems
using OrderedCollections

# bones, mice, kidney have missings in data
test_examples = [
    :rats,
    :pumps,
    :dogs,
    :seeds,
    :surgical_realistic,
    :magnesium,
    :salm,
    :equiv,
    :dyes,
    :stacks,
    :epil,
    :blockers,
    :oxford,
    :lsat,
    :bones,
    :mice,
    :kidney,
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

function _create_bugsmodel_with_consistent_sorted_nodes(
    model::JuliaBUGS.BUGSModel, reconstructed_model_def
)
    pass = CollectSortedNodes(model.evaluation_env)
    JuliaBUGS.analyze_block(pass, reconstructed_model_def)
    sorted_nodes = pass.sorted_nodes
    sorted_parameters = [vn for vn in sorted_nodes if vn in model.parameters]
    new_flattened_graph_node_data = JuliaBUGS.FlattenedGraphNodeData(model.g, sorted_nodes)
    new_model = BangBang.setproperty!!(model, :parameters, sorted_parameters)
    new_model = BangBang.setproperty!!(
        new_model, :flattened_graph_node_data, new_flattened_graph_node_data
    )
    return new_model
end

@testset "source_gen: $example_name" for example_name in test_examples
    model, evaluation_env = _create_model(example_name)
    lowered_model_def, reconstructed_model_def = _generate_lowered_model_def(
        model.model_def, model.g, evaluation_env
    )
    log_density_computation_expr = _gen_log_density_computation_function_expr(
        lowered_model_def, evaluation_env, gensym(example_name)
    )
    log_density_computation_function = eval(log_density_computation_expr)

    model_with_consistent_sorted_nodes = _create_bugsmodel_with_consistent_sorted_nodes(
        model, reconstructed_model_def
    )
    result_with_old_model = JuliaBUGS.evaluate!!(model)[2]
    params = JuliaBUGS.getparams(model_with_consistent_sorted_nodes)
    result_with_bugsmodel = JuliaBUGS.evaluate!!(
        model_with_consistent_sorted_nodes, params
    )[2]
    result_with_log_density_computation_function = log_density_computation_function(
        evaluation_env, params
    )
    @test result_with_old_model ≈ result_with_bugsmodel
    @test result_with_log_density_computation_function ≈ result_with_bugsmodel
end

@testset "reserved variable names are rejected" begin
    @test_throws ErrorException JuliaBUGS.__check_for_reserved_names(
        @bugs begin
            __logp__ ~ dnorm(0, 1)
        end
    )
end
