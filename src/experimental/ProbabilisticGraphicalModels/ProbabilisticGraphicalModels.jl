module ProbabilisticGraphicalModels

using BangBang
using Graphs
using Distributions

include("bayesnet.jl")

export 
    BayesianNetwork,
    Factor,
    create_factor,
    multiply_factors,
    marginalize,
    add_stochastic_vertex!,
    add_deterministic_vertex!,
    add_edge!,
    condition,
    decondition,
    ancestral_sampling,
    is_conditionally_independent,
    variable_elimination

end
