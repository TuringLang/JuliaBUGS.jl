module BugsParser

include("bugsast.jl")
include("typechecker.jl")

# export @bugsast_str
export @bugsast
export infer_types

end # module
