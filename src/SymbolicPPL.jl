module SymbolicPPL

include("bugsast.jl")
include("typechecker.jl")
include("compiler.jl")
include("primitives.jl")
include("gibbs.jl")


# export @bugsast_str
export @bugsast, @bugsmodel_str
export infer_types

export compile_graphppl, SampleFromPrior

include("BUGSExamples/BUGSExamples.jl")


end # module
