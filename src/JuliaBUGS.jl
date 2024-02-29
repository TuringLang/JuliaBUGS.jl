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
using StaticArrays
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

@inline function check_input(::NamedTuple{Vs,T}) where {Vs,T}
    for VT in T.parameters
        if VT <: AbstractArray
            if !(eltype(VT) <: Union{Int,Float64,Missing})
                error(
                    "Data input supports only Int, Float64, or Missing types within arrays. Received: $VT",
                )
            end
        elseif VT ∉ (Int, Float64)
            error("Scalar inputs must be of type Int or Float64. Received: $VT")
        end
    end
end

"""
    merge_with_coalescence(c1::Union{Dict, NamedTuple}, c2::Union{Dict, NamedTuple}, output_NamedTuple::Bool=true)

Merge two collections, `c1` and `c2`, which can be either dictionaries or named tuples, into a single collection 
(dictionary or named tuple). The function assumes that the values in the input collections are either `Number` or 
`Array` with matching sizes. If a key exists in both `c1` and `c2`, the merged collection will contain the non-missing 
values from `c1` and `c2`. If a key exists only in one of the collections, the resulting collection will contain the 
key-value pair from the respective collection.

# Example
```jldoctest
julia> d1 = Dict(:a => [1, 2, missing], :b => 42);

julia> d2 = Dict(:a => [missing, 2, 4], :c => -1);

julia> d3 = Dict(:a => [missing, 3, 4], :c => -1); # value collision

julia> merge_with_coalescence(d1, d2, false)
Dict{Symbol, Any} with 3 entries:
  :a => [1, 2, 4]
  :b => 42
  :c => -1

julia> merge_with_coalescence(d1, d3, false)
ERROR: The arrays in key 'a' have different non-missing values at the same positions.
[...]
```
"""
function merge_with_coalescence(d1, d2, output_NamedTuple=true)
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
    merge_with_coalescence(u::NamedTuple, v::NamedTuple)

Merge two `NamedTuple`s, coalescing concrete and missing values, and raise an error if there is a value difference between the two `NamedTuple`s.

# Example
```jldoctest
julia> nt1 = (a = [1, 2, missing], b = 42);

julia> nt2 = (a = [missing, 2, 4], c = -1);

julia> nt3 = (a = [missing, 3, 4], c = -1); # value collision in array

julia> nt4 = (a = [1, 2, missing], b = 0); # value collision

julia> merge_with_coalescence(nt1, nt2)
(a = [1, 2, 4], b = 42, c = -1)

julia> merge_with_coalescence(nt1, nt3)
ERROR: The arrays in key 'a' have different non-missing values at the same positions.
[...]

julia> merge_with_coalescence(nt1, nt4)
ERROR: The value for key 'b' is different in the two dictionaries.
[...]
```
"""
function merge_with_coalescence(
    u::NamedTuple{V1,T1}, v::NamedTuple{V2,T2}
) where {V1,V2,T1,T2}
    unioned_keys = Base.union(keys(u), keys(v))
    intersected_keys = Base.intersect(keys(u), keys(v))

    coalesced_values = Vector{Union{Int,Float64,AbstractArray}}(undef, length(unioned_keys))
    for (i, k) in enumerate(unioned_keys)
        if k in intersected_keys
            if typeof(u[k]) ∈ (Int, Float64)
                if u[k] === v[k]
                    coalesced_values[i] = u[k]
                else
                    error("The value for key '$(k)' is different in the two dictionaries.")
                end
            else # array
                if size(u[k]) != size(v[k])
                    error(
                        "The size of the array for key '$(k)' is different in the two dictionaries.",
                    )
                end
                coalesced_array = similar(u[k], Union{eltype(u[k]),eltype(v[k])})
                for (i, val_pair) in enumerate(zip(u[k], v[k]))
                    if val_pair[1] isa Union{Int,Float64} &&
                        val_pair[2] isa Union{Int,Float64} &&
                        val_pair[1] != val_pair[2]
                        error(
                            "The arrays in key '$(k)' have different non-missing values at the same positions.",
                        )
                    end
                    coalesced_array[i] = coalesce(val_pair[1], val_pair[2])
                end
                coalesced_values[i] = map(identity, coalesced_array)
            end
        elseif k ∈ V1
            coalesced_values[i] = u[k]
        else
            coalesced_values[i] = v[k]
        end
    end

    return NamedTuple{Tuple(unioned_keys)}(Tuple(coalesced_values))
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
    if !(data isa NamedTuple)
        data = NamedTuple{Tuple(keys(data))}(values(data))
    end

    if !(inits isa NamedTuple)
        inits = NamedTuple{Tuple(keys(inits))}(values(inits))
    end

    check_input(data)
    check_input(inits)

    scalars, array_sizes = analyze_program(
        CollectVariables(model_def, data), model_def, data
    )
    has_new_val, transformed_variables = analyze_program(
        ConstantPropagation(scalars, array_sizes), model_def, data
    )
    while has_new_val
        has_new_val, transformed_variables = analyze_program(
            ConstantPropagation(false, transformed_variables), model_def, data
        )
    end
    array_bitmap, transformed_variables = analyze_program(
        PostChecking(data, transformed_variables), model_def, data
    )
    merged_data = merge_with_coalescence(deepcopy(data), transformed_variables)
    vars, array_sizes, array_bitmap, node_args, node_functions, dependencies = analyze_program(
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
