using JuliaBUGS
using JuliaBUGS.BUGSExamples: rats, leuk
using JuliaBUGS: generate_analysis_function

using MacroTools, BangBang, Distributions

using JuliaBUGS:
    DetermineArraySizes,
    CheckMultipleAssignments,
    ComputeTransformed,
    CountFreeVars,
    LoopIteration,
    DetectLoops

model_def = deepcopy(leuk.model_def)
data = leuk.data;

##

f_expr = generate_analysis_function(DetermineArraySizes(), model_def)
eval(f_expr)
all_vars, array_sizes = __determine_array_sizes(data)

f_expr = generate_analysis_function(CheckMultipleAssignments(), model_def)
eval(f_expr)
potential_conflict = __check_multiple_assignments(data, array_sizes)

eval_env = JuliaBUGS.create_evaluate_env(all_vars, data, array_sizes)

f_expr = JuliaBUGS.generate_analysis_function(ComputeTransformed(), model_def)
eval(f_expr)
eval_env = __compute_transformed!(eval_env)

JuliaBUGS.check_conflicts(eval_env, potential_conflict...)

eval_env = JuliaBUGS.concretize_eval_env_value_types(eval_env)

f_expr = generate_analysis_function(CountFreeVars(), model_def)
eval(f_expr)
num_deterministic_vars, num_stochastic_vars = __count_free_vars(eval_env)

simplified_model_def = JuliaBUGS.remove_scalar_transformed_variable_exprs(
    model_def, eval_env
)
simplified_model_def = JuliaBUGS.remove_array_transformed_variables_exprs(
    simplified_model_def, eval_env
)

f_expr = generate_analysis_function(LoopIteration(), simplified_model_def, eval_env)
eval(f_expr)
hot_map = __decide_deterministic_loop_iterations_hot_maps(eval_env)

simplified_model_def = JuliaBUGS.transform_expr_with_hot_map(simplified_model_def, hot_map)

f_expr = JuliaBUGS.generate_analysis_function(DetectLoops(), simplified_model_def, eval_env, num_deterministic_vars, num_stochastic_vars)
eval(f_expr)
results = __detect_loops(eval_env)
