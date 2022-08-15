module BugsModels

include("bugsast.jl")
include("typechecker.jl")

include("compiler.jl")

# export @bugsast_str
export @bugsast, @bugsmodel_str
export infer_types

export analyze_data!, resolve, resolve_ref_obj!, unroll_for_loops!, parse_logical_assignments!, get_sym_var

end # module
