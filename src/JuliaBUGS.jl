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
using UnPack
using ReverseDiff

import Base: ==, hash, Symbol, size
import Distributions: truncated

export @bugsast, @bugsmodel_str
export compile

# user defined functions and distributions are not supported yet
include("BUGSPrimitives/BUGSPrimitives.jl")
using JuliaBUGS.BUGSPrimitives:
    abs,
    cloglog,
    equals,
    exp,
    inprod,
    inverse,
    log,
    logdet,
    logfact,
    loggam,
    icloglog,
    logit,
    mexp,
    max,
    mean,
    min,
    phi,
    pow,
    sqrt,
    rank,
    ranked,
    round,
    sd,
    softplus,
    sort,
    _step,
    sum,
    trunc,
    sin,
    arcsin,
    arcsinh,
    cos,
    arccos,
    arccosh,
    tan,
    arctan,
    arctanh
using JuliaBUGS.BUGSPrimitives:
    dnorm,
    dlogis,
    dt,
    ddexp,
    dflat,
    dexp,
    dchisqr,
    dweib,
    dlnorm,
    dgamma,
    dpar,
    dgev,
    dgpar,
    df,
    dunif,
    dbeta,
    dmnorm,
    dmt,
    dwish,
    ddirich,
    dbern,
    dbin,
    dcat,
    dpois,
    dgeom,
    dnegbin,
    dbetabin,
    dhyper,
    dmulti,
    TDistShiftedScaled,
    Flat,
    LeftTruncatedFlat,
    RightTruncatedFlat,
    TruncatedFlat

include("bugsast.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("node_functions.jl")
include("graphs.jl")
include("logdensityproblems.jl")

include("BUGSExamples/BUGSExamples.jl")

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

function merge_dicts(d1::Dict, d2::Dict)
    merged_dict = Dict()

    for key in union(keys(d1), keys(d2))
        if haskey(d1, key) && haskey(d2, key)
            @assert (
                isa(d1[key], Array) && isa(d2[key], Array) && size(d1[key]) == size(d2[key])
            ) || (isa(d1[key], Number) && isa(d2[key], Number) && d1[key] == d2[key])
            merged_dict[key] = isa(d1[key], Array) ? coalesce.(d1[key], d2[key]) : d1[key]
        else
            merged_dict[key] = haskey(d1, key) ? d1[key] : d2[key]
        end
    end

    return merged_dict
end

"""
    compile(model_def, data, initializations; target=:logdensityproblem, ad_backend=:reversediff, compile_tape=false)

Compile a BUGS model into a log density problem.

# Arguments
- `model_def::Expr`: The BUGS model definition.
- `data::NamedTuple` or `Dict`: The data to be used in the model. If a NamedTuple is passed, it will be converted to a Dict.
- `initializations::NamedTuple` or `Dict`: The initial values for the model parameters. If a NamedTuple is passed, it will be converted to a Dict.
- `target` (optional, keyword): The target output format. Currently, only `:logdensityproblem` is supported.
- `ad_backend` (optional, keyword): The automatic differentiation (AD) backend to use. Currently, only `:reversediff` and `:none` are supported.
- `compile_tape` (optional, keyword): A boolean flag indicating whether to compile the computation graph for ReverseDiff. Defaults to `false`.

# Returns
- A `LogDensityProblem` object representing the compiled model.

# Errors
- Will error if `target` is not `:logdensityproblem`.
- Will error if `ad_backend` is not `:reversediff` or `:nothing`.
"""
function compile(model_def::Expr, data::NamedTuple, initializations::NamedTuple)
    return compile(model_def, Dict(pairs(data)), Dict(pairs(initializations)))
end
function compile(
    model_def::Expr,
    data::Dict,
    inits::Dict;
    target=:logdensityproblem,
    ad_backend=:reversediff,
    compile_tape=false
)
    check_input.((data, inits))
    target == :logdensityproblem || error("Only :logdensityproblem is supported for now")

    vars, array_sizes, transformed_variables, array_bitmap = program!(
        CollectVariables(), model_def, data
    )
    merged_data = merge_dicts(deepcopy(data), transformed_variables)
    vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = program!(
        NodeFunctions(vars, array_sizes, array_bitmap), model_def, merged_data
    )
    g = create_BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g))

    re = Base.invokelatest(
        create_varinfo, g, sorted_nodes, vars, array_sizes, merged_data, inits
    )
    if ad_backend == :none
        p = BUGSLogDensityProblem(re)
    elseif ad_backend == :reversediff
        p = Base.invokelatest(
            ADgradient, :ReverseDiff, BUGSLogDensityProblem(re); compile=Val(compile_tape)
        )
    else
        error("Only :reversediff is supported for now")
    end

    return p
end

end
