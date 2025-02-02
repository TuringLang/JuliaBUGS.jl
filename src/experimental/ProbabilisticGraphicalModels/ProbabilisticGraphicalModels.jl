module ProbabilisticGraphicalModels

using BangBang
using Graphs
using Distributions
using JuliaBUGS
using JuliaBUGS: BUGSGraph, VarName
using JuliaBUGS.MetaGraphsNext

import Graphs: edges
import JuliaBUGS.MetaGraphsNext: labels

include("bayesian_network.jl")
include("conditioning.jl")
include("functions.jl")

struct NodeInfo{F}
    is_stochastic::Bool
    is_observed::Bool
    node_function_expr::Expr
    node_function::F
    node_args::Tuple{Vararg{Symbol}}
    loop_vars::NamedTuple
end

export BayesianNetwork, condition, condition!, s
decondition,
decondition!,
ancestral_sampling,
is_conditionally_independent,
add_deterministic_vertex!,
add_stochastic_vertex!,
add_vertex!,
translate_BUGSGraph_to_BayesianNetwork
end
