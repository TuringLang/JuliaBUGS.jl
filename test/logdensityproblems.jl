using JuliaBUGS
using JuliaBUGS: CollectVariables, DependencyGraph, NodeFunctions, program!, BUGSLogDensityProblem, ArrayVariable, ArrayElement, ArraySlice
using AdvancedHMC
using ReverseDiff
using LogDensityProblems
using Statistics
using AdvancedMH
using LinearAlgebra
using Distributions
using BenchmarkTools
using NamedTupleTools
using BangBang
using Graphs
using Bijectionss
using ProgressMeter
##
include("../src/BUGSExamples/BUGSExamples.jl")
volume_i_examples = BUGSExamples.volume_i_examples;

##
v = volume_i_examples[:equiv];
model_def = v.model_def;
data = v.data; data = convert(Dict, data);
inits = v.inits[1]; inits = convert(Dict, inits);
##
p = compile(model_def, data, inits; compile_tape = false);
array_sizes = JuliaBUGS.pre_process_data(data);
vars, array_map, var_types, missing_elements = program!(CollectVariables(array_sizes), model_def, data);
dep_graph = program!(DependencyGraph(vars, array_map, missing_elements), model_def, data);
logical_node_args, logical_node_f_exprs, stochastic_node_args, stochastic_node_f_exprs, link_functions, array_variables = program!(NodeFunctions(data, vars, array_map, missing_elements), model_def, data);

##
function print_to_file(x, filepath="/home/sunxd/Workspace/JuliaBUGS_outputs/output.jl")
    open(filepath, "w+") do f
        ks = collect(keys(x))
        for k in ks
            v = x[k]
            println(f, k, " = ", v)
        end
    end
end

print_to_file(vars)
print_to_file(var_types)
# print_to_file(node_args)
print_to_file(logical_node_args, "/home/sunxd/Workspace/JuliaBUGS_outputs/logical_node_args.jl")
print_to_file(logical_node_f_exprs)
##
@run p = BUGSLogDensityProblem(vars, var_types, dep_graph, logical_node_args, logical_node_f_exprs, stochastic_node_args, stochastic_node_f_exprs, link_functions, array_variables, data, inits)
p = BUGSLogDensityProblem(vars, var_types, dep_graph, logical_node_args, logical_node_f_exprs, stochastic_node_args, stochastic_node_f_exprs, link_functions, array_variables, data, inits);
initial_θ = JuliaBUGS.gen_init_params(p);
logp = p(initial_θ)

## run all examples
report_file = "/home/sunxd/Workspace/JuliaBUGS_outputs/test_report.jl"
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
function test_all_examples(examples, report_file, examples_to_test)
    open(report_file, "w+") do f
        for k in examples_to_test
            v = examples[k]
            println(f, "Testing $(k) ...")
            model_def = v.model_def
            data = v.data
            inits = v.inits[1]
            try
                p = compile(model_def, data, inits; compile_tape = false)
                initial_θ = JuliaBUGS.gen_init_params(p)
                logp = p(initial_θ)
                println(f, "logp = ", logp)
            catch e
                println(f, "Error: ", e)
            end
            println(f)
        end
    end
end

test_all_examples(volume_i_examples, report_file, example_names)

## HMC
p = compile(model_def, data, init)
initial_θ = JuliaBUGS.gen_init_params(p)

D = LogDensityProblems.dimension(p)
n_samples, n_adapts = 2000, 1000

metric = AdvancedHMC.DiagEuclideanMetric(D)
hamiltonian = AdvancedHMC.Hamiltonian(metric, p, :ReverseDiff)

initial_ϵ = find_good_stepsize(hamiltonian, initial_θ)
integrator = Leapfrog(initial_ϵ)
proposal = NUTS{MultinomialTS,GeneralisedNoUTurn}(integrator)
adaptor = StanHMCAdaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(0.8, integrator))

samples, stats = sample(
    hamiltonian,
    proposal,
    initial_θ,
    n_samples,
    adaptor,
    n_adapts;
    drop_warmup=true,
    progress=true,
)
traces = [JuliaBUGS.transform_samples(p, sample) for sample in samples]
open("/home/sunxd/JuliaBUGS.jl/notebooks/output.jl", "w+") do f
    for k in p.parameters
        k_samples = [trace[k] for trace in traces]
        m = mean(k_samples)
        s = std(k_samples)
        println(f, k, " = ", m, " ± ", s)
    end
end
##

## RWMH
p = compile(model_def, data, init)
initial_θ = JuliaBUGS.gen_init_params(p)

D = LogDensityProblems.dimension(p)
spl = RWMH(MvNormal(zeros(D), I))
samples = sample(p, spl, 100000)

traces = [JuliaBUGS.transform_samples(p, sample.params) for sample in samples]
open("/home/sunxd/JuliaBUGS.jl/notebooks/output.jl", "w+") do f
    for k in p.parameters
        k_samples = [trace[k] for trace in traces]
        m = mean(k_samples)
        s = std(k_samples)
        println(f, k, " = ", m, " ± ", s)
    end
end
##