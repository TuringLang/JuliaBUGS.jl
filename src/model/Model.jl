module Model

using Accessors
using AbstractPPL
using BangBang
using Bijectors
using Distributions
using Graphs
using LinearAlgebra
using JuliaBUGS: JuliaBUGS, BUGSGraph, markov_blanket
using JuliaBUGS.BUGSPrimitives
using MetaGraphsNext
using Random

include("utils.jl")
include("bugsmodel.jl")
include("evaluation.jl")
include("abstractppl.jl")
include("logdensityproblems.jl")

export parameters, variables, initialize!, getparams, settrans, set_evaluation_mode
export evaluate_with_rng!!, evaluate_with_env!!, evaluate_with_values!!

end # Model
