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
include("/home/sunxd/JuliaBUGS.jl/src/BUGSExamples/BUGSExamples.jl");
volume_i_examples = JuliaBUGS.BUGSExamples.volume_i_examples;

##
# m = volume_i_examples[keys(volume_i_examples)[1]]
m = volume_i_examples[:dogs]
model_def = m[:model_def]
data = Dict(pairs(m[:data]));
inits = Dict(pairs(m[:inits][1]));
println(m.name)

##
vars, array_sizes, transformed_variables, array_bitmap = program!(CollectVariables(), model_def, data);
merged_data = merge_dicts(deepcopy(data), transformed_variables);
vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = program!(
    NodeFunctions(vars, array_sizes, array_bitmap), model_def, merged_data
);

function merge_dicts(d1::Dict, d2::Dict)
    merged_dict = Dict()

    for key in union(keys(d1), keys(d2))
        if haskey(d1, key) && haskey(d2, key)
            @assert (isa(d1[key], Array) && isa(d2[key], Array) && size(d1[key]) == size(d2[key])) || (isa(d1[key], Number) && isa(d2[key], Number) && d1[key] == d2[key])
            merged_dict[key] = isa(d1[key], Array) ? coalesce.(d1[key], d2[key]) : d1[key]
        else
            merged_dict[key] = haskey(d1, key) ? d1[key] : d2[key]
        end
    end

    return merged_dict
end
merge_dicts(data, transformed_variables)

s = 0
for(k, v) in transformed_variables
    k == :y && continue
    # find the number of elements that are not missing
    s += count(!ismissing, v)
end
s

##
g = create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies);
sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g));
vi, re = create_varinfo(g, sorted_nodes, vars, array_sizes, merge_dicts(data, transformed_variables), inits);
vi.logp
##
p = ADgradient(:ReverseDiff, BUGSLogDensityProblem(re); compile=Val(true));
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
function test_all_examples(examples, examples_to_test, print_to_stdout=false, report_file="/home/sunxd/JuliaBUGS.jl/debug_outputs/test_report.jl")
    output_stream = print_to_stdout ? stdout : open(report_file, "w+")

    p = Progress(length(examples_to_test), desc="Testing: ")

    try
        for k in examples_to_test
            ProgressMeter.next!(p, showvalues=[(:Example, k)])
            m = examples[k]
            println(output_stream, "Testing $(k) ...")
            model_def = m[:model_def]
            data = Dict(pairs(m[:data]));
            inits = Dict(pairs(m[:inits][1]));
            try
                vars, array_sizes, transformed_variables, array_bitmap = program!(CollectVariables(), model_def, data);
                pass = program!(NodeFunctions(vars, array_sizes, array_bitmap), model_def, merge_dicts(data, transformed_variables));
                vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = unpack(pass);
                g = create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies);
                sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g));
                vi, re = @invokelatest create_varinfo(g, sorted_nodes, vars, array_sizes, merge_dicts(data, transformed_variables), inits);
                println(output_stream, "logp: $(vi.logp)")
            catch e
                println(output_stream, "Error in example $(k): ", e)
            end
            println(output_stream)
        end
    finally
        if !print_to_stdout
            close(output_stream)
        end
    end
end

function test_single_example(examples, example_name)
    k = example_name
    m = examples[k]
    model_def = m[:model_def]
    data = Dict(pairs(m[:data]));
    inits = Dict(pairs(m[:inits][1]));
    vars, array_sizes, transformed_variables, array_bitmap = program!(CollectVariables(), model_def, data);
    pass = program!(NodeFunctions(vars, array_sizes, array_bitmap), model_def, data);
    vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = unpack(pass);
    g = create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies);
    sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g));
    vi, re = @invokelatest create_varinfo(g, sorted_nodes, vars, array_sizes, data, inits);
    println("logp: $(vi.logp)")
end
test_all_examples(volume_i_examples, example_names)
test_all_examples(volume_i_examples, (:rats,), true)

@run test_single_example(volume_i_examples, :bones)
##
@run p = compile(model_def, data, inits)
p = compile(model_def, data, inits)

D = LogDensityProblems.dimension(p);
logp, grad = LogDensityProblems.logdensity_and_gradient(p, rand(D))
logp = LogDensityProblems.logdensity(p, rand(D))

##
using DynamicHMC, Random
using MCMCChains, Statistics

results = mcmc_with_warmup(Random.GLOBAL_RNG, p, 1000)
chains = Chains(transpose(results.posterior_matrix), Symbol.(p.ℓ.re.parameters))
mean(chains[:beta_c])

##
using AdvancedHMC
using LinearAlgebra

D = LogDensityProblems.dimension(p); 
n_samples, n_adapts = 2_000, 1_000

initial_θ = rand(D)
metric = DiagEuclideanMetric(D)
hamiltonian = Hamiltonian(metric, p, ReverseDiff)
initial_ϵ = find_good_stepsize(hamiltonian, initial_θ)
integrator = Leapfrog(initial_ϵ)
proposal = NUTS{MultinomialTS, GeneralisedNoUTurn}(integrator)
adaptor = StanHMCAdaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(0.8, integrator))

samples, stats = sample(hamiltonian, proposal, initial_θ, n_samples, adaptor, n_adapts; progress=true, drop_warmup=true)

beta_c_samples = [samples[s][2] for s in 1:length(samples)]
stats = mean(beta_c_samples), std(beta_c_samples) # Reference result: mean 6.186, variance 0.1088
