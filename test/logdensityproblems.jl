using JuliaBUGS
using JuliaBUGS: CollectVariables, DependencyGraph, NodeFunctions, program!, BUGSLogDensityProblem
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
##
include("../src/BUGSExamples/BUGSExamples.jl")
volume_i_examples = BUGSExamples.volume_i_examples;

##
v = volume_i_examples[:bones];
# v = volume_i_examples[:rats];
model_def = v.model_def;
data = v.data; data = convert(Dict, data);
inits = v.inits[1]; inits = convert(Dict, inits);

# p = compile(model_def, data, inits)
array_sizes = JuliaBUGS.pre_process_data(data);
vars, array_map, var_types, missing_elements = program!(CollectVariables(array_sizes), model_def, data);
dep_graph = program!(DependencyGraph(vars, array_map, missing_elements), model_def, data);
node_args, node_f_exprs, link_functions = program!(NodeFunctions(vars, array_map, missing_elements), model_def, data);

function print_to_file(x, filepath="/home/sunxd/notebooks/output.jl")
    open(filepath, "w+") do f
        ks = collect(keys(x))
        for k in ks
            v = x[k]
            println(f, k, " = ", v)
        end
    end
end
print_to_file(node_f_exprs)
##
@run p = BUGSLogDensityProblem(vars, var_types, dep_graph, node_args, node_f_exprs, link_functions, data, inits)
p = BUGSLogDensityProblem(vars, var_types, dep_graph, node_args, node_f_exprs, link_functions, data, inits);
initial_θ = JuliaBUGS.gen_init_params(p)
print_to_file()
print_to_file(initial_θ, "/home/sunxd/notebooks/initial_θ.jl")

logp = p(initial_θ)

const report_file = "/home/sunxd/JuliaBUGS.jl/notebooks/test_report.jl"
example_names = (
    # :blockers,
    :bones,
    :dogs,
    # :dyes,
    :epil,
    :equiv,
    :inhalers,
    :kidney,
    :leuk,
    :leukfr,
    :lsat,
    :magnesium,
    :mice,
    :oxford,
    # :pumps,
    # :rats,
    :salm,
    # :seeds,
    :stacks,
    # :surgical_simple,
    # :surgical_realistic,
)
function test_all_examples(examples, report_file, examples_to_test)
    open(report_file, "w+") do f
        for k in example_names
            v = volume_i_examples[k]
            println(f, "Testing $(k) ...")
            model_def = v.model_def
            data = v.data
            inits = v.inits[1]
            try
                p = compile(model_def, data, inits)
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

function print_to_file(x, filepath="output.jl")
    file_path = "/home/sunxd/JuliaBUGS.jl/notebooks/" * filename
    open(file_path, "w+") do f
        ks = collect(keys(x))
        for k in ks
            v = x[k]
            println(f, k, " = ", v)
        end
    end
end

function test_BUGS_model_with_default_hmc(model_def, data, init)
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
end

function test_BUGS_model_with_default_mh(model_def, data, init)
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
end
