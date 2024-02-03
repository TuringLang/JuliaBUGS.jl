module Backend

using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using BangBang
using MacroTools
using Missings
using RuntimeGeneratedFunctions
using Setfield
using Graphs, MetaGraphsNext
RuntimeGeneratedFunctions.init(@__MODULE__)

include("./utils.jl")
include("./statement_types.jl")
include("./CompileState.jl")
include("./determine_array_sizes.jl")
include("./check_multiple_assignments.jl")
include("./compute_transformed.jl")

end # module
