module ProbabilisticGraphicalModels

using BangBang
using Graphs
using Distributions
using JuliaBUGS
using JuliaBUGS: BUGSGraph, VarName

include("bayesnet.jl")

export BayesianNetwork,
    add_stochastic_vertex!,
    add_deterministic_vertex!,
    add_edge!,
    condition,
    condition!,
    decondition,
    decondition!,
    ancestral_sampling,
    is_conditionally_independent,
    translate_BUGSGraph_to_BayesianNetwork,
    something
end # module ProbabilisticGraphicalModels
