module SymbolicExt

using BangBang
using Distributions
using DynamicPPL
using Graphs, MetaGraphsNext
using IfElse
using JuliaBUGS
using LinearAlgebra
using LogExpFunctions
using MacroTools
using Setfield
using SpecialFunctions
using Statistics
using Symbolics, SymbolicUtils
using Random

include("graphs.jl")
include("symbolics.jl")
include("transform_ast.jl")
include("compiler.jl")
include("array_interface.jl")
include("primitives.jl")
include("gibbs.jl")
include("distributions.jl")
include("todppl.jl")

export compile
export @register_function, @register_distribution

end # module
