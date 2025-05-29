module Model

using Accessors
using AbstractPPL
using BangBang
using Bijectors
using Graphs
using LinearAlgebra
using JuliaBUGS: BUGSGraph, markov_blanket
using MetaGraphsNext
using Random

include("utils.jl")
include("model.jl")
include("interface.jl")
include("evaluation.jl")
include("model_operations.jl")
include("serialization.jl")

export parameters, variables, initialize!, getparams, settrans, set_evaluation_mode

end # BUGSModel
