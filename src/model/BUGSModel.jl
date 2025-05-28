module Model

using Accessors
using AbstractPPL
using BangBang
using Bijectors
using Graphs
using LinearAlgebra
using JuliaBUGS: BUGSGraph, markov_blanket, check_input
using MetaGraphsNext
using Random

import JuliaBUGS: compile

include("utils.jl")
include("model.jl")
include("evaluation.jl")
include("model_operations.jl")
include("serialization.jl")

end # BUGSModel
