module JuliaBUGS

using AbstractPPL
using Bijectors
using BangBang
using Distributions
using DynamicPPL
using LinearAlgebra
using LogExpFunctions
using SpecialFunctions
using Statistics
using Setfield
using Graphs, MetaGraphsNext
using LogDensityProblems, LogDensityProblemsAD
using MacroTools
using ReverseDiff

import Base: ==, hash, Symbol, size

# user defined functions and distributions are not supported yet
include("BUGSPrimitives/BUGSPrimitives.jl")
using .BUGSPrimitives

include("bugsast.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("node_functions.jl")
include("graphs.jl")
include("logdensityproblems.jl")

export @bugsast, @bugsmodel_str

function check_data(data)
    for (k, v) in data
        if !isa(v, Array)
            v == missing && throw(ArgumentError("missing data: $k"))
        end
    end
end

function compile(model_def::Expr, data::NamedTuple, initializations::NamedTuple)
    return compile(model_def, Dict(pairs(data)), Dict(pairs(initializations)))
end
function compile(
    model_def::Expr, data::Dict, inits::Dict; target=:LogDensityProblems, compile_tape=true
)
    error("Not implemented")
end

end
