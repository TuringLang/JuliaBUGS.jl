module ProbabilisticGraphicalModels

using BangBang
using Graphs
using Distributions

include("bayesnet.jl")

export BayesianNetwork,
    Factor,
    create_factor,
    multiply_factors,
    marginalize,
    add_stochastic_vertex!,
    add_deterministic_vertex!,
    add_edge!,
    condition,
    decondition,
    variable_elimination

end
