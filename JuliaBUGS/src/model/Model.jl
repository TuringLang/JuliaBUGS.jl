module Model

using Accessors
using AbstractPPL
using BangBang
using Bijectors
using Distributions
using Graphs
using LinearAlgebra
using JuliaBUGS: JuliaBUGS, BUGSGraph
using JuliaBUGS.BUGSPrimitives
using LogExpFunctions
using MetaGraphsNext
using Random

include("utils.jl")
include("bugsmodel.jl")
include("evaluation.jl")
include("abstractppl.jl")
include("logdensityproblems.jl")

# Public user-facing API
export parameters, variables, initialize!, getparams, settrans
export set_evaluation_mode, set_observed_values!

# Evaluation mode types
export UseGraph, UseGeneratedLogDensityFunction, UseAutoMarginalization

# Internal evaluation functions (exported for testing, not re-exported to users)
export evaluate_with_rng!!, evaluate_with_env!!, evaluate_with_values!!
export evaluate_with_marginalization_rng!!,
    evaluate_with_marginalization_env!!, evaluate_with_marginalization_values!!

end # Model
