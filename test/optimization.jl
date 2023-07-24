using JuliaBUGS
using BenchmarkTools, Profile, ProfileView

model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].inits[1]

bugs_model = compile(model_def, data, inits)

@profile compile(bugs_model_def, data, inits)

open("./profile", "w+") do io
    Profile.print(io)
end
Profile.print()

JuliaBUGS.check_input.((data, inits))

ars, array_sizes, transformed_variables, array_bitmap = JuliaBUGS.program!(
    JuliaBUGS.CollectVariables(), model_def, data
)
merged_data = JuliaBUGS.merge_dicts(deepcopy(data), transformed_variables)

vars, array_sizes, transformed_variables, array_bitmap = JuliaBUGS.program!(
    JuliaBUGS.CollectVariables(), model_def, data_dict
)
merged_data = JuliaBUGS.merge_dicts(deepcopy(data_dict), transformed_variables)

@benchmark JuliaBUGS.program!(
    JuliaBUGS.NodeFunctions(vars, array_sizes, array_bitmap), model_def, merged_data
)

vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = JuliaBUGS.program!(
    JuliaBUGS.NodeFunctions(vars, array_sizes, array_bitmap), model_def, merged_data
)
g = BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g))
# return Base.invokelatest(
#     BUGSModel, g, sorted_nodes, vars, array_sizes, merged_data, inits
# )
# return BUGSModel(
#     g, sorted_nodes, vars, array_sizes, merged_data, inits
# )

@benchmark JuliaBUGS.compile(model_def, data, inits)

