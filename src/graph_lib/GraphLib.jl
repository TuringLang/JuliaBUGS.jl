module GraphLib

using JuliaBUGS.SemanticAnalysis
using JuliaBUGS.SemanticAnalysis:
    CompileState, Statement, ForStatement, all_statements, call
using MacroTools
using Graphs, MetaGraphsNext

include("./build_graph.jl")
include("./coarse_graph.jl")

end