module ProbabilisticGraphicalModels

using BangBang
using Graphs
using MetaGraphsNext
using Distributions
using JuliaBUGS
using JuliaBUGS: BUGSGraph, VarName, NodeInfo
using AbstractPPL

include("bayesian_network.jl")
include("conditioning.jl")
include("functions.jl")

export BayesianNetwork,
    condition,
    condition!,
    decondition,
    decondition!,
    ancestral_sampling,
    is_conditionally_independent,
    add_deterministic_vertex!,
    add_stochastic_vertex!,
    add_vertex!,
    translate_BUGSGraph_to_BayesianNetwork
end
