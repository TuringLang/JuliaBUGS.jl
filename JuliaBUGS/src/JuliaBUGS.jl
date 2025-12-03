module JuliaBUGS

using AbstractMCMC
using AbstractPPL
using Accessors
using ADTypes
using BangBang
using Bijectors: Bijectors
using DifferentiationInterface
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
import DifferentiationInterface as DI
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

function create_graph(model_def, eval_env, eval_module=Main)
    pass = AddVertices(model_def, eval_env, eval_module)
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
Manages the allowlist of functions that can be used in @bugs macro expressions.
Only functions in this allowlist or registered via @bugs_primitive are permitted.
"""
const BUGS_ALLOWED_FUNCTIONS = Set{Symbol}()

"""
    is_function_allowed(func_name::Symbol)

Check if a function is allowed to be used in @bugs expressions.
"""
is_function_allowed(func_name::Symbol) = func_name in BUGS_ALLOWED_FUNCTIONS

"""
    validate_bugs_expression(expr, line_num)

Validate that all function calls in the expression are allowed.
Throws an error if an unregistered function is found.
"""
function validate_bugs_expression(expr, line_num)
    if expr isa Symbol || expr isa Number
        return nothing  # Base cases are fine
    elseif Meta.isexpr(expr, :call)
        func_name = expr.args[1]

        # Check for qualified function names (e.g., Base.exp, Distributions.Normal)
        if Meta.isexpr(func_name, :.)
            qualified_expr = func_name
            unqualified_name =
                if Meta.isexpr(qualified_expr, :.) && length(qualified_expr.args) >= 2
                    # For expressions like Base.exp, extract :exp
                    qualified_expr.args[2].value
                else
                    qualified_expr
                end
            error(
                "Qualified function names are not supported in @bugs. Found $(qualified_expr) at $line_num. " *
                "To use custom functions, declare them with @bugs_primitive macro. " *
                "Otherwise, use the unqualified function name `$(unqualified_name)` instead.",
            )
        elseif func_name isa Symbol && !is_function_allowed(func_name)
            error(
                "Function '$func_name' is not allowed in @bugs at $line_num. " *
                "To use custom functions, declare them with @bugs_primitive macro.",
            )
        end
        # Recursively validate arguments
        for arg in expr.args[2:end]
            validate_bugs_expression(arg, line_num)
        end
    elseif Meta.isexpr(expr, :ref)
        # Validate array indexing expressions
        for arg in expr.args
            validate_bugs_expression(arg, line_num)
        end
    elseif Meta.isexpr(expr, :block)
        # Validate block expressions
        for arg in expr.args
            if !(arg isa LineNumberNode)
                validate_bugs_expression(arg, line_num)
            end
        end
    elseif Meta.isexpr(expr, :for)
        # Validate for loop expressions
        validate_bugs_expression(expr.args[2], line_num)  # loop body
    elseif Meta.isexpr(expr, :(=))
        # For assignments, validate both LHS (in case of array indexing) and RHS
        validate_bugs_expression(expr.args[1], line_num)
        validate_bugs_expression(expr.args[2], line_num)
    end
end

"""
    compile(model_def, data[, initial_params]; skip_validation=false, adtype=nothing)

Compile the model with model definition and data. Optionally, initializations can be provided.
If initializations are not provided, values will be sampled from the prior distributions.

By default, validates that all functions in the model are in the BUGS allowlist (suitable for @bugs macro).
Set `skip_validation=true` to skip validation (for @model macro usage).

The compiled model uses `UseGraph` evaluation mode by default. To use the optimized generated
log-density function, call `set_evaluation_mode(model, UseGeneratedLogDensityFunction())`.

If `adtype` is provided, returns a `BUGSModelWithGradient` that supports gradient-based MCMC
samplers like HMC/NUTS. The gradient computation is prepared during compilation for optimal performance.

# Arguments
- `model_def::Expr`: Model definition from @bugs macro
- `data::NamedTuple`: Observed data
- `initial_params::NamedTuple=NamedTuple()`: Initial parameter values (optional)
- `skip_validation::Bool=false`: Skip function validation (for @model macro)
- `eval_module::Module=@__MODULE__`: Module for evaluation
- `adtype`: AD backend specification using ADTypes. Examples:
  - `AutoReverseDiff(compile=true)` - ReverseDiff with tape compilation (fastest)
  - `AutoReverseDiff(compile=false)` - ReverseDiff without compilation
  - `AutoForwardDiff()` - ForwardDiff backend
  - `AutoZygote()` - Zygote backend
  - `AutoEnzyme()` - Enzyme backend
  - `AutoMooncake()` - Mooncake backend
  - Any other `ADTypes.AbstractADType`

# Examples
```julia
# Basic compilation
model = compile(model_def, data)

# With gradient support using ReverseDiff (recommended for most models)
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))

# Using ForwardDiff for small models
model = compile(model_def, data; adtype=AutoForwardDiff())

# Sample with NUTS
chain = AbstractMCMC.sample(model, NUTS(0.8), 1000)
```
"""
function compile(
    model_def::Expr,
    data::NamedTuple,
    initial_params::NamedTuple=NamedTuple();
    skip_validation::Bool=false,
    eval_module::Module=@__MODULE__,
    adtype::Union{Nothing,ADTypes.AbstractADType,Symbol}=nothing,
)
    # Validate functions by default (for @bugs macro usage)
    # Skip validation only for @model macro
    if !skip_validation
        validate_bugs_expression(model_def, LineNumberNode(0))
    end

    data = check_input(data)
    eval_env = semantic_analysis(model_def, data)
    model_def = concretize_colon_indexing(model_def, eval_env)
    g = create_graph(model_def, eval_env, eval_module)
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
    base_model = BUGSModel(g, nonmissing_eval_env, model_def, data, initial_params, true)

    # If adtype provided, wrap with gradient capabilities
    if adtype !== nothing
        return _wrap_with_gradient(base_model, adtype)
    end

    return base_model
end

# Helper function to prepare gradient - separated to handle world age issues
function _wrap_with_gradient(base_model::Model.BUGSModel, adtype::ADTypes.AbstractADType)
    # Use invokelatest to handle world age issues with generated functions
    return Base.invokelatest(Model.BUGSModelWithGradient, base_model, adtype)
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
    register_bugs_function(func_name::Symbol)

Register a function to be allowed in @bugs expressions.
Used by @bugs_primitive macro.
"""
function register_bugs_function(func_name::Symbol)
    push!(BUGS_ALLOWED_FUNCTIONS, func_name)
end

"""
Helper function to generate the expression for registering a single bugs primitive
"""
function _bugs_primitive_expr(func::Symbol, esc_func)
    return quote
        local f = $esc_func
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

"""
    @bugs_primitive(func)

`@bugs_primitive` can also be used to register functions without definition.
"""
macro bugs_primitive(func::Symbol)
    return _bugs_primitive_expr(func, esc(func))
end

macro bugs_primitive(funcs::Vararg{Symbol})
    exprs = [_bugs_primitive_expr(func, esc(func)) for func in funcs]
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
    empty!(BUGS_ALLOWED_FUNCTIONS)

    for name in names(BUGSPrimitives; all=false)
        if isdefined(BUGSPrimitives, name)
            push!(BUGS_ALLOWED_FUNCTIONS, name)
        end
    end

    for func in [
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
        push!(BUGS_ALLOWED_FUNCTIONS, func)
    end

    # Add basic operators
    for op in [:+, :-, :*, :/, :^, :~, :>, :<, :>=, :<=, :(==), :!, :(:)]
        push!(BUGS_ALLOWED_FUNCTIONS, op)
    end
end

end
