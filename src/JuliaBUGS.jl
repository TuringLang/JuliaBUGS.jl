module JuliaBUGS

using AbstractPPL
using Accessors
using AdvancedHMC
using BangBang
using Bijections
using Bijectors
using Distributions
using LinearAlgebra
using LogExpFunctions
using SpecialFunctions
using Statistics
using Graphs
using LogDensityProblems, LogDensityProblemsAD
using MacroTools
using ReverseDiff

using RuntimeGeneratedFunctions
RuntimeGeneratedFunctions.init(@__MODULE__)

import Base: in, push!, ==, hash, Symbol, keys, size

export @bugsast, @bugsmodel_str

include("BUGSPrimitives/BUGSPrimitives.jl")
using .BUGSPrimitives

macro register_function(ex)
    eval_registration(ex)
end

macro register_distribution(ex)
    eval_registration(ex)
end

function eval_registration(ex)
    def = MacroTools.splitdef(ex)
    reg_sym = Expr(
        :macrocall,
        Symbol("@register_symbolic"),
        LineNumberNode(@__LINE__, @__FILE__),
        Expr(:call, def[:name], def[:args]...),
    )
    eval(reg_sym)
    eval(ex)
    return def[:name]
end

include("bugsast.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("utils.jl")
include("passes/collect_variables.jl")
include("passes/dependency_graph.jl")
include("passes/node_functions.jl")
include("targets/logdensityproblems.jl")

function compile(model_def::Expr, data::NamedTuple, initializations::NamedTuple)
    return compile(model_def, Dict(pairs(data)), Dict(pairs(initializations)))
end
function compile(model_definition::Expr, data::Dict, initializations::Dict; target=:LogDensityProblems)
    vars, array_map, var_types = program!(CollectVariables(), model_definition, data)
    dep_graph = program!(DependencyGraph(vars, array_map), model_definition, data)
    node_args, node_functions, link_functions = program!(NodeFunctions(vars, array_map), model_definition, data)

    p = BUGSLogDensityProblem(vars, var_types, dep_graph, node_args, node_functions, link_functions, data, initializations)
    inputs = gen_init_params(p)
    f_tape = ReverseDiff.GradientTape(p, inputs)
    compiled_tape = ReverseDiff.compile(f_tape)
    all_results = ReverseDiff.DiffResults.GradientResult(inputs)
    cfg = ReverseDiff.GradientConfig(inputs)
    p = @set p.compiled_tape = compiled_tape
    p = @set p.gradient_cfg = cfg
    p = @set p.all_results = all_results
    
    return p
end

export compile

end
