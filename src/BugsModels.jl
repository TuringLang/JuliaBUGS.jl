module BugsModels

include("bugsast.jl")
include("typechecker.jl")
include("compiler.jl")
include("distributions.jl")

# export @bugsast_str
export @bugsast, @bugsmodel_str
export infer_types

export compile_graphppl

end # module
