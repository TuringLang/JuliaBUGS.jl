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

function check_input(input::NamedTuple)
    for (k, v) in pairs(input)
        if v isa AbstractArray
            if !(eltype(v) <: Union{Int,Float64,Missing})
                error(
                    "For array input, only Int, Float64, or Missing types are supported. Received: $(typeof(v)).",
                )
            end
        elseif v === missing
            error("Scalars cannot be missing. Received: $k")
        elseif !(v isa Union{Int,Float64})
            error("Scalars must be of type Int or Float64. Received: $k")
        end
    end
    return input
end
function check_input(input::Dict{KT,VT}) where {KT,VT}
    if KT === Symbol
        return check_input(NamedTuple(input))
    else
        ks = map(identity, keys(input))
        if eltype(ks) === Symbol
            return check_input(NamedTuple(ks, vs))
        else
            error(
                "When the input isa Dict, the keys must be of type Symbol. Received: $(typeof(ks)).",
            )
        end
    end
end
function check_input(input)
    return error("Input must be of type NamedTuple or Dict. Received: $(typeof(input)).")
end

function compute_data_transformation(
    non_data_scalars, non_data_array_sizes, model_def, data
)
    eval_env = create_eval_env(non_data_scalars, non_data_array_sizes, data)
    has_new_val = true
    while has_new_val
        has_new_val = analyze_program(DataTransformation(false), model_def, eval_env)
    end
    return concretize_eval_env(eval_env)
end

function finish_checking_repeated_assignments(
    conflicted_scalars, conflicted_arrays, merged_data
)
    # finish up repeated assignment check now we have transformed data
    for scalar in conflicted_scalars
        if merged_data[scalar] isa Missing
            error("$scalar is assigned by both logical and stochastic variables.")
        end
    end

    for (array_name, conflict_array) in pairs(conflicted_arrays)
        missing_values = ismissing.(merged_data[array_name])
        conflicts = conflict_array .& missing_values
        if any(conflicts)
            error(
                "$(array_name)[$(join(Tuple.(findall(conflicts)), ", "))] is assigned by both logical and stochastic variables.",
            )
        end
    end
end

"""
    compile(model_def, data, initializations; is_transformed=true)

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
    data, inits = check_input(data), check_input(inits)

    eval_env = semantic_analysis(model_def, data)
    model_def = concretize_colon_indexing(model_def, eval_env)

    g = build_graph(model_def, eval_env)
    sorted_nodes = map(Base.Fix1(label_for, g), topological_sort(g))
    return BUGSModel(g, sorted_nodes, eval_env, inits; is_transformed=is_transformed)
end

function semantic_analysis(model_def::Expr, data)
    non_data_scalars, non_data_array_sizes = analyze_program(
        CollectVariables(model_def, data), model_def, data
    )
    conflicted_scalars, conflicted_arrays = analyze_program(
        CheckRepeatedAssignments(model_def, data, non_data_array_sizes), model_def, data
    )
    eval_env = compute_data_transformation(
        non_data_scalars, non_data_array_sizes, model_def, data
    )
    finish_checking_repeated_assignments(conflicted_scalars, conflicted_arrays, eval_env)
    return eval_env
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
