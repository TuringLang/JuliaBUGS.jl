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
using Graphs, MetaGraphsNext
using LogDensityProblems, LogDensityProblemsAD
using MacroTools
using ReverseDiff

using RuntimeGeneratedFunctions
RuntimeGeneratedFunctions.init(@__MODULE__)

import Base: in, push!, ==, hash, Symbol, keys, size, isless

export @bugsast, @bugsmodel_str

include("BUGSPrimitives/BUGSPrimitives.jl")
using .BUGSPrimitives

macro register_function(ex)
    return eval_registration(ex)
end

macro register_distribution(ex)
    return eval_registration(ex)
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
include("passes/collect_variables.jl")
include("passes/dependency_graph.jl")
include("passes/node_functions.jl")
include("targets/logdensityproblems.jl")

# TODO: adapt DataFrames.jl

function pre_process_data(data::Dict)
    array_sizes = Dict()
    
    for (k, v) in data
        if v isa AbstractArray
            array_sizes[k] = collect(size(v))
        end
    end

    return array_sizes
end

function compile(model_def::Expr, data::NamedTuple, initializations::NamedTuple)
    return compile(model_def, Dict(pairs(data)), Dict(pairs(initializations)))
end
function compile(
    model_def::Expr, data::Dict, inits::Dict; target = :LogDensityProblems, compile_tape = true
)
    array_sizes = pre_process_data(data)
    vars, array_map, var_types, missing_elements = program!(CollectVariables(array_sizes), model_def, data);
    dep_graph = program!(DependencyGraph(vars, array_map, missing_elements), model_def, data);
    logical_node_args, logical_node_f_exprs, stochastic_node_args, stochastic_node_f_exprs, link_functions, array_variables = program!(NodeFunctions(data, vars, array_map, missing_elements), model_def, data);

    p = BUGSLogDensityProblem(vars, var_types, dep_graph, logical_node_args, logical_node_f_exprs, stochastic_node_args, stochastic_node_f_exprs, link_functions, array_variables, data, inits);
    if compile_tape
        inputs = gen_init_params(p)
        f_tape = ReverseDiff.GradientTape(p, inputs)
        compiled_tape = ReverseDiff.compile(f_tape)
        all_results = ReverseDiff.DiffResults.GradientResult(inputs)
        cfg = ReverseDiff.GradientConfig(inputs)
        p = @set p.compiled_tape = compiled_tape
        p = @set p.gradient_cfg = cfg
        p = @set p.all_results = all_results
    end
    return p
end

export compile

end
