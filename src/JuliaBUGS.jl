module JuliaBUGS

using AbstractMCMC
using AbstractPPL
using BangBang
using Bijectors
using Distributions
using Graphs
using LogDensityProblems, LogDensityProblemsAD
using MacroTools
using MetaGraphsNext
using Random
using Setfield
using UnPack

using DynamicPPL: DynamicPPL, SimpleVarInfo

import Base: ==, hash, Symbol, size
import Distributions: truncated
import AbstractPPL: AbstractContext, evaluate!!

export @bugs
export compile

export @varname

# user defined functions and distributions are not supported yet
include("BUGSPrimitives/BUGSPrimitives.jl")
using .BUGSPrimitives

include("parser/Parser.jl")
using .Parser

include("utils.jl")
include("variable_types.jl")
include("compiler_pass.jl")
include("graphs.jl")
include("model.jl")
include("logdensityproblems.jl")
include("gibbs.jl")

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

Merge two collections, `c1` and `c2`, which can be either dictionaries or named tuples, into a single collection 
(dictionary or named tuple). The function assumes that the values in the input collections are either `Number` or 
`Array` with matching sizes. If a key exists in both `c1` and `c2`, the merged collection will contain the non-missing 
values from `c1` and `c2`. If a key exists only in one of the collections, the resulting collection will contain the 
key-value pair from the respective collection.

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
- `data::NamedTuple` or `AbstractDict`: The data to be used in the model. If none is passed, the data will be assumed to be empty.
- `initializations::NamedTuple` or `AbstractDict`: The initial values for the model parameters. If none is passed, the parameters will be assumed to be initialized to zero.
- `is_transformed::Bool=true`: If true, the model parameters during inference will be transformed to the unconstrained space. 

# Returns
- A [`BUGSModel`](@ref) object representing the compiled model.
"""
function compile(model_def::Expr, data, inits; is_transformed=true)
    check_input.((data, inits))
    scalars, array_sizes = program!(CollectVariables(), model_def, data)
    has_new_val, transformed_variables = program!(
        ConstantPropagation(scalars, array_sizes), model_def, data
    )
    while has_new_val
        has_new_val, transformed_variables = program!(
            ConstantPropagation(false, transformed_variables), model_def, data
        )
    end
    array_bitmap, transformed_variables = program!(
        PostChecking(data, transformed_variables), model_def, data
    )
    merged_data = merge_collections(deepcopy(data), transformed_variables)
    vars, array_sizes, array_bitmap, node_args, node_functions, dependencies = program!(
        NodeFunctions(array_sizes, array_bitmap), model_def, merged_data
    )
    g = create_BUGSGraph(vars, node_args, node_functions, dependencies)
    sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g))
    return BUGSModel(
        g,
        sorted_nodes,
        vars,
        array_sizes,
        merged_data,
        inits;
        is_transformed=is_transformed,
    )
end

"""
    @register_primitive(expr)

Currently, only function defined in the `BUGSPrimitives` module can be used in the model definition. 
This macro allows the user to register a user-defined function or distribution to be used in the model definition.

Example:
```julia
julia> @register_primitive function f(x) # function
    return x + 1
end

julia> JuliaBUGS.f(1)
2

julia> @register_primitive d(x) = Normal(0, x^2) # distribution

julia> JuliaBUGS.d(1)
Distributions.Normal{Float64}(μ=0.0, σ=1.0)
```
"""
macro register_primitive(expr)
    def = MacroTools.splitdef(expr)
    func_name = def[:name]
    func_expr = MacroTools.combinedef(def)
    return quote
        @eval JuliaBUGS begin
            # export $func_name
            $func_expr
        end
    end
end

"""
    @register_primitive(func)

`@register_primitive` can also be used to register function without definition.

Example
```julia
julia> f(x) = x + 1

julia> @register_primitive(f)

julia> JuliaBUGS.f(1)
2
```
"""
macro register_primitive(func::Symbol)
    return quote
        @eval JuliaBUGS begin
            $func = Main.$func
        end
    end
end
macro register_primitive(funcs::Vararg{Symbol})
    exprs = Expr(:block)
    for func in funcs
        push!(exprs.args, :($func = Main.$func))
    end
    return quote
        @eval JuliaBUGS begin
            $exprs
        end
    end
end

"""
    gen_chains

Generate a `Chains` object from the samples and statistics generated by `AbstractMCMC.sample`.
Only defined with `MCMCChains` extension.
"""
function gen_chains end

end
