using StaticArrays: StaticArrays
using MacroTools: prewalk, postwalk, @q, @qq

include("generate_function_expr.jl")
include("utils.jl")
include("determine_array_sizes.jl")
include("check_multiple_assignments.jl")
include("compute_transformed.jl")
include("count_free_vars.jl")
include("loop_iterations.jl")
include("detect_loops.jl")
