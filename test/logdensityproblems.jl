using JuliaBUGS: create_BUGSGraph, create_varinfo
using Graphs, MetaGraphsNext
using ReverseDiff
using LogDensityProblems, LogDensityProblemsAD
using JuliaBUGS: BUGSLogDensityProblem
using DynamicPPL

using MCMCChains, Statistics
##
g = create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies);
sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g));
vi, re = create_varinfo(g, sorted_nodes, vars, array_sizes, data, inits);
p = ADgradient(:ReverseDiff, BUGSLogDensityProblem(re); compile=Val(true));

##
using DynamicHMC, Random

results = mcmc_with_warmup(Random.GLOBAL_RNG, p, 1000)
chains = Chains(transpose(results.posterior_matrix), Symbol.(p.ℓ.re.parameters))
mean(chains[:beta_c])

##
using AdvancedHMC
using LinearAlgebra

# Choose parameter dimensionality and initial parameter value
D = LogDensityProblems.dimension(p); 
initial_θ = rand(D)

# Set the number of samples to draw and warmup iterations
n_samples, n_adapts = 2_000, 1_000

# Define a Hamiltonian system
metric = DiagEuclideanMetric(D)
hamiltonian = Hamiltonian(metric, p, ReverseDiff)

# Define a leapfrog solver, with initial step size chosen heuristically
initial_ϵ = find_good_stepsize(hamiltonian, initial_θ)
integrator = Leapfrog(initial_ϵ)

# Define an HMC sampler, with the following components
#   - multinomial sampling scheme,
#   - generalised No-U-Turn criteria, and
#   - windowed adaption for step-size and diagonal mass matrix
proposal = NUTS{MultinomialTS, GeneralisedNoUTurn}(integrator)
adaptor = StanHMCAdaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(0.8, integrator))

# Run the sampler to draw samples from the specified Gaussian, where
#   - `samples` will store the samples
#   - `stats` will store diagnostic statistics for each sample
samples, stats = sample(hamiltonian, proposal, initial_θ, n_samples, adaptor, n_adapts; progress=true, drop_warmup=true)

beta_c_samples = [samples[s][2] for s in 1:length(samples)]
stats = mean(beta_c_samples), std(beta_c_samples) # Reference result: mean 6.186, variance 0.1088
