module GraphLib

using JuliaBUGS: JuliaBUGS, SemanticAnalysis
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.SemanticAnalysis:
    CompileState, Statement, ForStatement, all_statements, call, simplify_lhs
using MacroTools
using Graphs, MetaGraphsNext

using RuntimeGeneratedFunctions
RuntimeGeneratedFunctions.init(@__MODULE__)

include("./build_graph.jl")
include("./coarse_graph.jl")

end