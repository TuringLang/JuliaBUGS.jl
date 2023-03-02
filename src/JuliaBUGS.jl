module JuliaBUGS

using AbstractPPL
using Bijections
using Bijectors
using Distributions
using Graphs
using LogDensityProblems, LogDensityProblemsAD
using MacroTools

import Base: in, push!, ==, hash, Symbol, keys, size

export @bugsast, @bugsmodel_str

include("BUGSPrimitives/BUGSPrimitives.jl")

using .BUGSPrimitives

include("bugsast.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("utils.jl")
include("passes/collect_variables.jl")
include("passes/dependency_graph.jl")
include("passes/node_functions.jl")
include("targets/logdensityproblems.jl")


function compile(model_definition, data, initializations)
    vars, array_map, var_types = program!(CollectVariables(), model_definition, data)
    dep_graph = program!(DependencyGraph(vars, array_map), model_definition, data)
    node_args, node_functions, link_functions = program!(NodeFunctions(vars, array_map), model_definition, data)

    return BUGSModel(vars, array_map, var_types, dep_graph, node_args, node_functions, link_functions, data, initializations)
end

export compile

end
