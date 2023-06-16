using JuliaBUGS
using JuliaBUGS: create_BUGSGraph, create_varinfo, compile, merge_dicts
using JuliaBUGS: program!, CollectVariables, NodeFunctions
using Graphs, MetaGraphsNext
using ReverseDiff
using LogDensityProblems, LogDensityProblemsAD
using JuliaBUGS: BUGSLogDensityProblem
using DynamicPPL
using ProgressMeter
##
function compile_single(example_name)
    example = getfield(JuliaBUGS.BUGSExamples.volume_i_examples, example_name)
    model_def = example.model_def
    data = Dict(pairs(example.data));
    inits = Dict(pairs(example.inits[1]));

    p = compile(model_def, data, inits);
    return p
end

function compile_single_spilled(example_name)
    example = getfield(JuliaBUGS.BUGSExamples.volume_i_examples, example_name)
    model_def = example.model_def
    data = Dict(pairs(example.data));
    inits = Dict(pairs(example.inits[1]));

    vars, array_sizes, transformed_variables, array_bitmap = program!(
        CollectVariables(), model_def, data
    )
    merged_data = JuliaBUGS.merge_dicts(deepcopy(data), transformed_variables)
    vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = program!(
        NodeFunctions(vars, array_sizes, array_bitmap), model_def, merged_data
    )
    g = create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g))
    re = Base.invokelatest(
        create_varinfo, g, sorted_nodes, vars, array_sizes, merged_data, inits
    )
    return re
end

##
example_names = (
    :blockers,
    :bones,
    :dogs,
    :dyes,
    :epil,
    :equiv,
    # :inhalers,
    :kidney,
    :leuk,
    :leukfr,
    :lsat,
    :magnesium,
    :mice,
    :oxford,
    :pumps,
    :rats,
    :salm,
    :seeds,
    :stacks,
    :surgical_simple,
    :surgical_realistic,
)

##
p = compile_single(:rats)
using LogDensityProblemsAD
fieldnames(typeof(p))
p.ℓ.re.prototype

for example_name in example_names
    @show example_name
    try
        p = compile_single(example_name)
        @show p.ℓ.re.prototype
    catch e
        @show e
    end
end

re = compile_single_spilled(:bones)
re.prototype