module JuliaBUGS

using AbstractPPL
using Distributions
using Graphs
using MacroTools

import Base: in, push!, ==, hash, Symbol

export @bugsast

include("bugsast.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("utils.jl")
include("passes/collect_variables.jl")
include("passes/dependency_graph.jl")
include("passes/node_functions.jl")
include("BUGSPrimitives/BUGSPrimitives.jl")

end
