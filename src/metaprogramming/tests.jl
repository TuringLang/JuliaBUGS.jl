using JuliaBUGS
using JuliaBUGS.BUGSExamples: rats, leuk
using JuliaBUGS: generate_analysis_function

using JuliaBUGS: DetermineArraySizes, CheckMultipleAssignments, ComputeTransformed

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


