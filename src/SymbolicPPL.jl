module SymbolicPPL

include("bugsast.jl")
include("graph.jl")
include("compiler.jl")
include("primitives.jl")
include("gibbs.jl")
include("distributions.jl")
include("toturing.jl")


export @bugsast, @bugsmodel_str
export compile, compile_inter, querynode
export getDAG, getnodeenum, getnodename, getnumnodes, getsortednodes, getmarkovblanket, getchidren, getparents, 
    shownodefunc, getdistribution, @nodename
export toturing, inspect_toturing
export @primitive, @bugsdistribution
export SampleFromPrior

include("BUGSExamples/BUGSExamples.jl")
using .BUGSExamples
export EXAMPLES, LINKS

end # module
