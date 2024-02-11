module SemanticAnalysis

using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using BangBang
using MacroTools
using Missings
using Setfield # TODO: move to Accessors
using ComponentArrays

include("./utils.jl")
include("./simplify_lhs.jl")
include("./statement_types.jl")
# include("./CompileState.jl")
include("./determine_array_sizes.jl")
# include("./check_multiple_assignments.jl")
# include("./compute_transformed.jl")

# include("./special_case.jl")

end # module
