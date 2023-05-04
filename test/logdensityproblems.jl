using JuliaBUGS: create_BUGSGraph, initialize_vi, create_varinfo
using Graphs, MetaGraphsNext
using ReverseDiff
using BenchmarkTools
using LogDensityProblems, LogDensityProblemsAD
using JuliaBUGS: BUGSLogDensityProblem
##

g = create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies);
sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g));
vi, re = create_varinfo(g, sorted_nodes, vars, array_sizes, data, inits);
p = ADgradient(:ReverseDiff, BUGSLogDensityProblem(re); compile=Val(true))

LogDensityProblems.logdensity(p, rand(LogDensityProblems.dimension(p)))