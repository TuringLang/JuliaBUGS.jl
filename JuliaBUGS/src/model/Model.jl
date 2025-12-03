module Model

using Accessors
using AbstractPPL
using ADTypes
using BangBang
using Bijectors
import DifferentiationInterface as DI
using Distributions
using Graphs
using LinearAlgebra
using JuliaBUGS: JuliaBUGS, BUGSGraph
using JuliaBUGS.BUGSPrimitives
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
export UseGraph, UseGeneratedLogDensityFunction

# Gradient wrapper
export BUGSModelWithGradient

end # Model
