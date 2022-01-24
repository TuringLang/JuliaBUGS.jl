module BugsParser

include("bugsast.jl")
include("typechecker.jl")

# export @bugsast_str
export @bugsast, @bugsmodel_str
export infer_types

end # module
