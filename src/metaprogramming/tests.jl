using JuliaBUGS
using JuliaBUGS.BUGSExamples: rats, leuk
using JuliaBUGS:
    @_bugs,
    gen_deter_arr_sizes_func,
    gen_check_multiple_assignments_func,
    gen_compute_transformed_func

model_def = deepcopy(leuk.model_def)
data = leuk.data;
##

f_expr = gen_deter_arr_sizes_func(model_def)
eval(f_expr)
array_sizes = __determine_array_sizes(data)

f_expr = gen_check_multiple_assignments_func(model_def)
eval(f_expr)
potential_conflict = __check_multiple_assignments__(data, array_sizes)

f_expr = JuliaBUGS.gen_compute_transformed_func(model_def)
eval(f_expr)
env = __compute_transformed(data, array_sizes)
