module BugsParser

# include("parser.jl")
include("jbugs.jl")
include("typechecker.jl")

# export @bugsast_str
export @bugsast
export infer_types

end # module
