module SymbolicPPL

include("bugsast.jl")
include("graphinfo.jl")
include("compiler.jl")
include("primitives.jl")
include("gibbs.jl")

# export @bugsast_str
export @bugsast, @bugsmodel_str
export infer_types

export compile_graphppl, SampleFromPrior

include("BUGSExamples/BUGSExamples.jl")
using .BUGSExamples
export EXAMPLES, LINKS

end # module
