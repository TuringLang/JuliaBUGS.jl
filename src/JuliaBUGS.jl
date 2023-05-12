module JuliaBUGS

using AbstractPPL
using Bijectors
using BangBang
using Distributions
using DynamicPPL
using LinearAlgebra
using LogExpFunctions
using SpecialFunctions
using Statistics
using Setfield
using Graphs, MetaGraphsNext
using LogDensityProblems, LogDensityProblemsAD
using MacroTools
using ReverseDiff

import Base: ==, hash, Symbol, size

# user defined functions and distributions are not supported yet
include("BUGSPrimitives/BUGSPrimitives.jl")
using .BUGSPrimitives

include("bugsast.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("node_functions.jl")
include("graphs.jl")
include("logdensityproblems.jl")

export @bugsast, @bugsmodel_str

export compile

function check_input(input::Union{NamedTuple,Dict})
    for (k, v) in input
        @assert k isa Symbol
        # v has three possibilities: 1. number 2. array of numbers 3. array mixed with numbers and missing
        # check this
        if v isa Number
            continue
        elseif v isa AbstractArray
            for i in v
                @assert i isa Number || ismissing(i)
            end
        else
            error("Input $k is not a number or an array of numbers")
        end
    end
end

function compile(model_def::Expr, data::NamedTuple, initializations::NamedTuple)
    return compile(model_def, Dict(pairs(data)), Dict(pairs(initializations)))
end
function compile(
    model_def::Expr, data::Dict, inits::Dict; target=:logdensityproblem, ad_backend=:reversediff
)
    check_input.((data, inits))

    target == :logdensityproblem || error("Only :logdensityproblem is supported for now")

    vars, array_sizes, transformed_variables, array_bitmap = program!(
        CollectVariables(), model_def, data
    )
    pass = program!(NodeFunctions(vars, array_sizes, array_bitmap), model_def, data)

    vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = unpack(
        pass
    )
    g = create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g))
    
    vi, re = @invokelatest create_varinfo(g, sorted_nodes, vars, array_sizes, data, inits)
    if ad_backend == :none
        p = BUGSLogDensityProblem(re)
    elseif ad_backend == :reversediff
        p = @invokelatest ADgradient(:ReverseDiff, BUGSLogDensityProblem(re); compile=Val(true))
    else
        error("Only :reversediff is supported for now")
    end
    
    return p
end

end
