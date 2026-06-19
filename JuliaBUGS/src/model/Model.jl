module Model

using AbstractMCMC
using Accessors
using AbstractPPL
using ADTypes
using BangBang
using Bijectors
using Distributions
using Graphs
using LinearAlgebra
using JuliaBUGS: JuliaBUGS, BUGSGraph, find_generated_quantities_variables
using JuliaBUGS.BUGSPrimitives
using LogExpFunctions
using MetaGraphsNext
using OrderedCollections: OrderedDict
using Random

include("utils.jl")
include("bugsmodel.jl")
include("evaluation.jl")
include("abstractppl.jl")
include("logdensityproblems.jl")
include("abstractmcmc.jl")
include("to_distribution.jl")

# Public user-facing API
export parameters, variables, initialize!, getparams, settrans, to_distribution
export set_evaluation_mode, set_observed_values!
export model_parameters, generated_quantities, variable_type

# Variable classification
export VariableType, Observation, ModelParameter, TransformedParameter, GeneratedQuantity

# Evaluation mode types
export UseGraph, UseGeneratedLogDensityFunction, UseAutoMarginalization

# Gradient wrapper
export BUGSModelWithGradient

# Internal evaluation functions (exported for testing, not re-exported to users)
export evaluate_with_rng!!, evaluate_with_env!!, evaluate_with_values!!
export evaluate_with_marginalization_values!!

end # Model
