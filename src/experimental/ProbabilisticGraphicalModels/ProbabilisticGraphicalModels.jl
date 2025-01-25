module ProbabilisticGraphicalModels

using BangBang
using Graphs
using Distributions

include("bayesian_network.jl")
include("conditioning.jl")
include("functions.jl")

export BayesianNetwork,
    condition,
    condition!,
    decondition,
    decondition!,
    ancestral_sampling,
    is_conditionally_independent

end