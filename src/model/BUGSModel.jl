module Model

using AbstractPPL
using BangBang
using JuliaBUGS: BUGSGraph
using Random
using Accessors

include("model.jl")
include("evaluation.jl")
include("model_operations.jl")
include("serialization.jl")

end # BUGSModel
