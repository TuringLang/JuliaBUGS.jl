module JuliaBUGS

using AbstractPPL
using Bijections
using Distributions
using Graphs
using MacroTools

import Base: in, push!, ==, hash, Symbol, keys

export @bugsast

include("bugsast.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("utils.jl")
include("passes/collect_variables.jl")
include("passes/dependency_graph.jl")
include("passes/node_functions.jl")
include("logdensity.jl")
include("BUGSPrimitives/BUGSPrimitives.jl")

# TODO: can be just a Vector indexed by the id of the variable, a further optimization can be done is give elements from the same array continuous ids
struct Trace end

end
