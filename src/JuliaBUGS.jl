module JuliaBUGS

using AbstractMCMC
using AbstractPPL
using BangBang
using Bijectors
using Distributions
using DynamicPPL
using Graphs
using LogDensityProblems
using MacroTools
using MetaGraphsNext
using Random
using Setfield
using UnPack

import Base: ==, hash, Symbol, size
import Distributions: truncated
import AbstractPPL: AbstractContext, evaluate!!
import DynamicPPL: settrans!!

export @bugsast, @bugsmodel_str
export compile

# user defined functions and distributions are not supported yet
include("BUGSPrimitives/BUGSPrimitives.jl")
using .BUGSPrimitives

include("bugsast.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("node_functions.jl")
include("bijectors.jl")
include("graphs.jl")
include("logdensityproblems.jl")

include("BUGSExamples/BUGSExamples.jl")

function check_input(input::Union{NamedTuple, AbstractDict})
    for (k, v) in input
        @assert k isa Symbol "Variable name $k must be a Symbol"

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

"""
    merge_dicts(d1::Dict, d2::Dict) -> Dict

Merge two dictionaries, `d1` and `d2`, into a single dictionary. The function assumes that the values in
the input dictionaries are either `Number` or `Array` with matching sizes. If a key exists in both `d1` and `d2`,
the merged dictionary will contain the non-missing values from `d1` and `d2`. If a key exists only in one of the
dictionaries, the resulting dictionary will contain the key-value pair from the respective dictionary.

# Arguments
- `d1::Dict`: The first dictionary to merge.
- `d2::Dict`: The second dictionary to merge.

# Returns
- `merged_dict::Dict`: A new dictionary containing the merged key-value pairs from `d1` and `d2`.

# Example
```jldoctest
julia> d1 = Dict("a" => [1, 2, missing], "b" => 42);

julia> d2 = Dict("a" => [missing, 2, 4], "c" => -1);

julia> d3 = Dict("a" => [missing, 3, 4], "c" => -1); # value collision

julia> merge_dicts(d1, d2)
Dict{Any, Any} with 3 entries:
  "c" => -1
  "b" => 42
  "a" => [1, 2, 4]

julia> merge_dicts(d1, d3)
ERROR: The arrays in key 'a' have different non-missing values at the same positions.
[...]
```
"""
function merge_dicts(d1::Dict, d2::Dict)
    merged_dict = Dict()

    for key in Base.union(keys(d1), keys(d2))
        in_both_dicts = haskey(d1, key) && haskey(d2, key)
        values_match_type =
            in_both_dicts && (
                (
                    isa(d1[key], Array) &&
                    isa(d2[key], Array) &&
                    size(d1[key]) == size(d2[key])
                ) || (isa(d1[key], Number) && isa(d2[key], Number) && d1[key] == d2[key])
            )

        if values_match_type
            if isa(d1[key], Array)
                # Check if any position has different non-missing values in the two arrays.
                if !all(
                    i -> (
                        ismissing(d1[key][i]) ||
                        ismissing(d2[key][i]) ||
                        d1[key][i] == d2[key][i]
                    ),
                    1:length(d1[key]),
                )
                    error(
                        "The arrays in key '$(key)' have different non-missing values at the same positions.",
                    )
                end
                merged_value = coalesce.(d1[key], d2[key])
            else
                merged_value = d1[key]
            end

            merged_dict[key] = merged_value
        else
            merged_dict[key] = haskey(d1, key) ? d1[key] : d2[key]
        end
    end

    return merged_dict
end

"""
    compile(model_def[, data, initializations])

Compile a BUGS model into a log density problem.

# Arguments
- `model_def::Expr`: The BUGS model definition.
- `data::NamedTuple` or `Dict`: The data to be used in the model. If none is passed, the data will be assumed to be empty.
- `initializations::NamedTuple` or `Dict`: The initial values for the model parameters. If none is passed, the parameters will be assumed to be initialized to zero.

# Returns
- A [`BUGSModel`](@ref) object representing the compiled model.
"""
function compile(model_def::Expr, data::Union{NamedTuple, AbstractDict}, initializations::Union{NamedTuple, AbstractDict})
    return compile(model_def, Dict(pairs(data)), Dict(pairs(initializations)))
end
function compile(model_def::Expr, data::AbstractDict, inits::AbstractDict)
    check_input.((data, inits))
    vars, array_sizes, transformed_variables, array_bitmap = program!(
        CollectVariables(), model_def, data
    )
    merged_data = merge_dicts(deepcopy(data), transformed_variables)
    vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = program!(
        NodeFunctions(vars, array_sizes, array_bitmap), model_def, merged_data
    )
    g = BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g))
    return Base.invokelatest(
        BUGSModel, g, sorted_nodes, vars, array_sizes, merged_data, inits
    )
    # return BUGSModel(
    #     g, sorted_nodes, vars, array_sizes, merged_data, inits
    # )
end
compile(model_def::Expr, data::NamedTuple) = compile(model_def, Dict(pairs(data)), Dict())
compile(model, data::Dict) = compile(model, data, Dict())
compile(model_def::Expr) = compile(model_def, Dict(), Dict())

end
