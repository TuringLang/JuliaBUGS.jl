module JuliaBUGS

using AbstractMCMC
using AbstractPPL
using Accessors
using ADTypes
using BangBang
using Bijectors: Bijectors
using Distributions
using Graphs, MetaGraphsNext
using LinearAlgebra
using LogDensityProblems, LogDensityProblemsAD
using MacroTools
using OrderedCollections: OrderedDict
using Random
using Serialization: Serialization
using StaticArrays

import Base: ==, hash, Symbol, size
import Distributions: truncated

export @bugs
export compile, initialize!

export @varname
export @model
export @of

include("BUGSPrimitives/BUGSPrimitives.jl")
using .BUGSPrimitives

include("parser/Parser.jl")
using .Parser
using .Parser.CompilerUtils

include("graphs.jl")
include("compiler_pass.jl")
include("model/Model.jl")
using .Model
using .Model:
    AbstractBUGSModel,
    BUGSModel,
    evaluate_with_values!!,
    UseGraph,
    UseGeneratedLogDensityFunction

include("independent_mh.jl")
include("gibbs.jl")

include("source_gen.jl")
include("allowed_functions.jl")

include("BUGSExamples/BUGSExamples.jl")

function check_input(input::NamedTuple)
    valid_pairs = Pair{Symbol,Any}[]
    for (k, v) in pairs(input)
        if v === missing
            continue # Skip missing values
        elseif v isa AbstractArray
            # Allow arrays containing Int, Float64, or Missing
            allowed_eltypes = Union{Int,Float64,Missing}
            if !(eltype(v) <: allowed_eltypes)
                error(
                    "For array input '$k', only elements of type $allowed_eltypes are supported. Received array with eltype: $(eltype(v)).",
                )
            end
            push!(valid_pairs, k => v)
        elseif v isa Union{Int,Float64}
            # Allow scalar Int or Float64
            push!(valid_pairs, k => v)
        else
            # Error for other scalar types
            error(
                "Scalar input '$k' must be of type Int or Float64. Received: $(typeof(v))."
            )
        end
    end
    return NamedTuple(valid_pairs)
end
function check_input(input::Dict{KT,VT}) where {KT,VT}
    if isempty(input)
        return NamedTuple()
    end
    if KT === Symbol
        return check_input(NamedTuple(input))
    else
        ks = map(identity, collect(keys(input)))
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

function determine_array_sizes(model_def, data)
    pass = CollectVariables(model_def, data)
    analyze_block(pass, model_def; warn_loop_bounds=Ref(true))
    non_data_scalars, non_data_array_sizes = post_process(pass)
    return non_data_scalars, non_data_array_sizes
end

function check_repeated_assignments(model_def, data, array_sizes)
    pass = CheckRepeatedAssignments(model_def, data, array_sizes)
    analyze_block(pass, model_def)
    conflicted_scalars, conflicted_arrays = post_process(pass)
    return conflicted_scalars, conflicted_arrays
end

function compute_data_transformation(
    non_data_scalars, non_data_array_sizes, model_def, data
)
    eval_env = create_eval_env(non_data_scalars, non_data_array_sizes, data)
    has_new_val = true
    pass = DataTransformation(eval_env, false, Ref(false))
    while has_new_val
        pass.new_value_added = false
        analyze_block(pass, model_def)
        has_new_val = pass.new_value_added
    end
    return concretize_eval_env(pass.env)
end

function finish_checking_repeated_assignments(
    conflicted_scalars, conflicted_arrays, eval_env
)
    for scalar in conflicted_scalars
        if eval_env[scalar] isa Missing
            error("$scalar is assigned by both logical and stochastic variables.")
        end
    end

    for (array_name, conflict_array) in pairs(conflicted_arrays)
        missing_values = ismissing.(eval_env[array_name])
        conflicts = conflict_array .& missing_values
        if any(conflicts)
            error(
                "$(array_name)[$(join(Tuple.(findall(conflicts)), ", "))] is assigned by both logical and stochastic variables.",
            )
        end
    end
end

function create_graph(model_def, eval_env)
    pass = AddVertices(model_def, eval_env)
    analyze_block(pass, model_def)
    pass = AddEdges(pass.env, pass.g, pass.vertex_id_tracker)
    analyze_block(pass, model_def)
    return pass.g
end

function semantic_analysis(model_def, data)
    non_data_scalars, non_data_array_sizes = determine_array_sizes(model_def, data)
    conflicted_scalars, conflicted_arrays = check_repeated_assignments(
        model_def, data, non_data_array_sizes
    )
    eval_env = compute_data_transformation(
        non_data_scalars, non_data_array_sizes, model_def, data
    )
    finish_checking_repeated_assignments(conflicted_scalars, conflicted_arrays, eval_env)
    return eval_env
end

"""
    compile(model_def, data[, initial_params]; from_model_macro=false)

Compile the model with model definition and data. Optionally, initializations can be provided. 
If initializations are not provided, values will be sampled from the prior distributions.

By default, validates that all functions in the model are in the BUGS allowlist (suitable for @bugs macro).
Set `from_model_macro=true` to skip validation (for @model macro usage).
"""
function compile(
    model_def::Expr,
    data::NamedTuple,
    initial_params::NamedTuple=NamedTuple();
    from_model_macro::Bool=false,
)
    # Validate functions by default (for @bugs macro usage)
    # Skip validation only for @model macro
    if !from_model_macro
        validate_bugs_expression(model_def, LineNumberNode(0))
    end

    data = check_input(data)
    eval_env = semantic_analysis(model_def, data)
    model_def = concretize_colon_indexing(model_def, eval_env)
    g = create_graph(model_def, eval_env)
    nonmissing_eval_env = NamedTuple{keys(eval_env)}(
        map(
            v -> begin
                if v === missing
                    return 0.0
                elseif v isa AbstractArray
                    if eltype(v) === Missing
                        return zeros(size(v)...)
                    elseif Missing <: eltype(v)
                        return coalesce.(v, zero(nonmissingtype(eltype(v))))
                    end
                end
                return v
            end,
            values(eval_env),
        ),
    )
    return BUGSModel(g, nonmissing_eval_env, model_def, data, initial_params)
end
# function compile(
#     model_str::String,
#     data::NamedTuple,
#     initial_params::NamedTuple=NamedTuple();
#     replace_period::Bool=true,
#     no_enclosure::Bool=false,
# )
#     model_def = _bugs_string_input(model_str, replace_period, no_enclosure)
#     return compile(model_def, data, initial_params)
# end

"""
    @bugs_primitive(expr)

Currently, only function defined in the `BUGSPrimitives` module can be used in the model definition. 
This macro allows the user to register a user-defined function or distribution to be used in the model definition.

Example:
```julia
julia> @bugs_primitive function f(x) # function
    return x + 1
end

julia> JuliaBUGS.f(1)
2

julia> @bugs_primitive d(x) = Normal(0, x^2) # distribution

julia> JuliaBUGS.d(1)
Distributions.Normal{Float64}(μ=0.0, σ=1.0)
```
"""
macro bugs_primitive(expr)
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
    @bugs_primitive(func)

`@bugs_primitive` can also be used to register function without definition.

Example
```julia
julia> f(x) = x + 1

julia> @bugs_primitive(f)

julia> JuliaBUGS.f(1)
2
```
"""
macro bugs_primitive(func::Symbol)
    return quote
        local f = $(esc(func))
        # Check if it's callable by checking if it has methods
        if length(methods(f)) == 0
            error("@bugs_primitive: $($(QuoteNode(func))) is not callable")
        end
        # Add to the allowed functions set
        JuliaBUGS.register_bugs_function($(QuoteNode(func)))
        # Also add to JuliaBUGS module for direct access (if not already defined)
        if !isdefined(JuliaBUGS, $(QuoteNode(func)))
            Core.eval(JuliaBUGS, Expr(:const, Expr(:(=), $(QuoteNode(func)), f)))
        end
        nothing
    end
end
macro bugs_primitive(funcs::Vararg{Symbol})
    exprs = []
    for func in funcs
        push!(
            exprs,
            quote
                local f = $(esc(func))
                # Check if it's callable by checking if it has methods
                if length(methods(f)) == 0
                    error("@bugs_primitive: $($(QuoteNode(func))) is not callable")
                end
                # Add to the allowed functions set
                JuliaBUGS.register_bugs_function($(QuoteNode(func)))
                # Also add to JuliaBUGS module for direct access (if not already defined)
                if !isdefined(JuliaBUGS, $(QuoteNode(func)))
                    Core.eval(JuliaBUGS, Expr(:const, Expr(:(=), $(QuoteNode(func)), f)))
                end
                nothing
            end,
        )
    end
    return Expr(:block, exprs...)
end

"""
    gen_chains

Generate a `Chains` object from the samples and statistics generated by `AbstractMCMC.sample`.
Only defined with `MCMCChains` extension.
"""
function gen_chains end

include("of_type.jl")
include("model_macro.jl")

export of

include("serialization.jl")

include("experimental/ProbabilisticGraphicalModels/ProbabilisticGraphicalModels.jl")

function __init__()
    # Initialize the allowed functions set with BUGSPrimitives exports
    empty!(BUGS_ALLOWED_FUNCTIONS)

    # Add all exported functions from BUGSPrimitives
    for name in names(BUGSPrimitives; all=false)
        if isdefined(BUGSPrimitives, name)
            push!(BUGS_ALLOWED_FUNCTIONS, name)
        end
    end

    # Add BUGS scalar functions that might come from Base or other modules
    # These are documented BUGS functions that users expect to work
    scalar_functions = [
        :abs,
        :arccos,
        :arccosh,
        :arcsin,
        :arcsinh,
        :arctan,
        :arctanh,
        :cloglog,
        :cos,
        :cosh,
        :cumulative,
        :cut,
        :density,
        :deviance,
        :equals,
        :exp,
        :gammap,
        :ilogit,
        :icloglog,
        :integral,
        :log,
        :logfact,
        :loggam,
        :logit,
        :max,
        :min,
        :phi,
        :pow,
        :probit,
        :round,
        :sin,
        :sinh,
        :solution,
        :sqrt,
        :step,
        :tan,
        :tanh,
        :trunc,
        :sum,
        :mean,
    ]

    for func in scalar_functions
        push!(BUGS_ALLOWED_FUNCTIONS, func)
    end

    # Add basic operators
    for op in [:+, :-, :*, :/, :^, :~, :>, :<, :>=, :<=, :(==), :!, :(:)]
        push!(BUGS_ALLOWED_FUNCTIONS, op)
    end
end

end
