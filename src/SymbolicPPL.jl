module SymbolicPPL

include("bugsast.jl")
include("graphs.jl")
include("compiler.jl")
include("primitives.jl")
include("gibbs.jl")
include("distributions.jl")
include("todppl.jl")

export @bugsast, @bugsmodel_str
export compile
export @register_function, @register_distribution

include("BUGSExamples/BUGSExamples.jl")

end # module
