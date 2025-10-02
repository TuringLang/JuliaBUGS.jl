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

export parameters, variables, initialize!, getparams, settrans, set_evaluation_mode
export regenerate_log_density_function, set_observed_values!
export evaluate_with_rng!!, evaluate_with_env!!, evaluate_with_values!!
export BUGSModelWithGradient, _logdensity_switched

end # Model
