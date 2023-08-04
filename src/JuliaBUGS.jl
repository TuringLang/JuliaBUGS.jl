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

export @varname

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

function check_input(input::Union{NamedTuple,AbstractDict})
    for k in keys(input)
        @assert k isa Symbol "Variable name $k must be a Symbol"

        v = input[k]
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
    merge_collections(c1::Union{Dict, NamedTuple}, c2::Union{Dict, NamedTuple}, output_NamedTuple::Bool=true) -> Union{Dict, NamedTuple}

Merge two collections, `c1` and `c2`, which can be either dictionaries or named tuples, into a single collection (dictionary or named tuple). The function assumes that the values in the input collections are either `Number` or `Array` with matching sizes. If a key exists in both `c1` and `c2`, the merged collection will contain the non-missing values from `c1` and `c2`. If a key exists only in one of the collections, the resulting collection will contain the key-value pair from the respective collection.

# Arguments
- `c1::Union{Dict, NamedTuple}`: The first collection to merge.
- `c2::Union{Dict, NamedTuple}`: The second collection to merge.
- `output_NamedTuple::Bool=true`: Determines the type of the output collection. If true, the function outputs a NamedTuple. If false, it outputs a Dict.

# Returns
- `merged::Union{Dict, NamedTuple}`: A new collection containing the merged key-value pairs from `c1` and `c2`.

# Example
```jldoctest
julia> d1 = Dict(:a => [1, 2, missing], :b => 42);

julia> d2 = Dict(:a => [missing, 2, 4], :c => -1);

julia> d3 = Dict(:a => [missing, 3, 4], :c => -1); # value collision

julia> merge_collections(d1, d2, false)
Dict{Symbol, Any} with 3 entries:
  :a => [1, 2, 4]
  :b => 42
  :c => -1

julia> merge_collections(d1, d3, false)
ERROR: The arrays in key 'a' have different non-missing values at the same positions.
[...]
```
"""
function merge_collections(d1, d2, output_NamedTuple=true)
    merged_dict = Dict{Symbol,Any}()

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

    if output_NamedTuple
        return NamedTuple{Tuple(keys(merged_dict))}(values(merged_dict))
    else
        return merged_dict
    end
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
function compile(model_def::Expr, data, inits)
    check_input.((data, inits))
    vars, array_sizes, transformed_variables, array_bitmap = program!(
        CollectVariables(), model_def, data
    )
    merged_data = merge_collections(deepcopy(data), transformed_variables)
    vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = program!(
        NodeFunctions(vars, array_sizes, array_bitmap), model_def, merged_data
    )
    g = BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g))
    return BUGSModel(g, sorted_nodes, vars, array_sizes, merged_data, inits)
end

end
