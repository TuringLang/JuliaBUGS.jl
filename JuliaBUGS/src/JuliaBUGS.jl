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
using LogDensityProblems
using MacroTools
using OrderedCollections: OrderedDict
using Random
using Serialization: Serialization
using StaticArrays

import Base: ==, hash, Symbol, size
import Distributions: truncated

import AbstractPPL: of
using AbstractPPL: @of, unflatten, _validate, get_names

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

"""
    BUGSModelDef

Callable wrapper around the model-definition AST produced by [`@bugs`](@ref) (or the
string form `@bugs"..."`). Calling it with a data `NamedTuple` compiles the model, so
`@bugs`/`@bugs_str` behave like `@model`: a model definition is a callable that returns a
`BUGSModel`.

```julia
model_def = @bugs begin
    x ~ dnorm(0, 1)
end
model = model_def((;))              # equivalent to `compile(model_def, (;))`
model = model_def(data, inits)      # start from given initial values
model = model_def(data; adtype=AutoMooncake(; config=nothing))   # attach a gradient backend
```

The optional second positional argument is a `NamedTuple` of initial parameter values
(defaulting to prior samples); it is useful when random draws from vague priors would
otherwise land outside a distribution's support during construction.

The underlying `Expr` stays accessible via the `model_def` field for introspection,
serialization, and source generation.
"""
struct BUGSModelDef
    model_def::Expr
end

Base.show(io::IO, ::BUGSModelDef) = print(io, "BUGSModelDef(…)")

function Base.show(io::IO, ::MIME"text/plain", m::BUGSModelDef)
    println(io, "BUGSModelDef:")
    return print(io, m.model_def)
end

"""
    @bugs(program::Expr)
    @bugs(program::String, replace_period::Bool=true, no_enclosure::Bool=false)

Construct a [`BUGSModelDef`](@ref) from a BUGS model given as a Julia `begin ... end` block
or as a string of BUGS source. The result is *callable*: passing a data `NamedTuple`
compiles it into a `BUGSModel` (equivalently, `compile(model_def, data)`).

- When given an expression, syntactic checks ensure compatibility with BUGS syntax.
- When given a string, it is parsed as a BUGS program. `replace_period` (default `true`)
  replaces `.` in names; `no_enclosure` (default `false`), when `true`, drops the
  requirement that the program be wrapped in `model { ... }`.

See also [`BUGSModelDef`](@ref), [`compile`](@ref), [`@model`](@ref).
"""
macro bugs(expr::Expr)
    Parser.warn_cumulative_density_deviance(expr)
    ast = Parser.bugs_top(expr, __source__)
    return :($(BUGSModelDef)($(Meta.quot(ast))))
end

macro bugs(prog::String, replace_period::Bool=true, no_enclosure::Bool=false)
    ast = Parser._bugs_string_input(prog, replace_period, no_enclosure)
    return :($(BUGSModelDef)($(Meta.quot(ast))))
end

include("graphs.jl")
include("compiler_pass.jl")
include("model/Model.jl")
using .Model
using .Model: AbstractBUGSModel, BUGSModel
export to_distribution

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
    compile(model_def, data[, initial_params]; adtype=nothing)

Compile a BUGS model. Returns `BUGSModel`, or `BUGSModelWithGradient` if `adtype` is provided.

# Arguments
- `model_def`: Model definition — a [`BUGSModelDef`](@ref) from [`@bugs`](@ref), or the underlying `Expr`
- `data::NamedTuple`: Observed data
- `initial_params::NamedTuple`: Initial parameter values (optional, defaults to prior samples)
- `adtype`: AD backend from ADTypes.jl (e.g., `AutoMooncake()`, `AutoReverseDiff()`, `AutoForwardDiff()`)

For Mooncake-backed AD, load `Mooncake` before compiling with `adtype`. For
DifferentiationInterface-backed AD backends like `AutoReverseDiff()` and
`AutoForwardDiff()`, load `DifferentiationInterface` and the concrete backend
package before compiling.

# Examples
```julia
model = compile(model_def, data)

using ADTypes, Mooncake
model = compile(model_def, data; adtype=AutoMooncake(; config=nothing))

using ADTypes, DifferentiationInterface, ReverseDiff
model = compile(model_def, data; adtype=AutoReverseDiff())
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
        return Base.invokelatest(Model.BUGSModelWithGradient, base_model, adtype)
    end

    return base_model
end

function compile(model_def::BUGSModelDef, args...; kwargs...)
    return compile(model_def.model_def, args...; kwargs...)
end
function (model_def::BUGSModelDef)(
    data::NamedTuple=(;), initial_params::NamedTuple=NamedTuple(); kwargs...
)
    return compile(model_def.model_def, data, initial_params; kwargs...)
end

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

Generate a chains object from the samples and statistics generated by `AbstractMCMC.sample`.

With the `MCMCChains` extension loaded, `gen_chains(model, samples, stats_names, stats_values; kwargs...)`
returns an `MCMCChains.Chains`. With the `FlexiChains` extension loaded,
`gen_chains(FlexiChains.VNChain, model, samples, stats_names, stats_values; kwargs...)`
returns a `FlexiChains.FlexiChain{VarName}` keyed by variable name (array-valued
variables are stored whole instead of being flattened into scalar columns).
"""
function gen_chains end

"""
    of(model::BUGSModel)

Extract the `of` type specification from a compiled `BUGSModel`.

This function introspects the model's evaluation environment to reconstruct the corresponding
`of` type specification. This is useful for:
- Model introspection and debugging
- Type validation after compilation
- Generic code that needs to work with models without knowing their structure
- Model serialization and deserialization

# Arguments
- `model::BUGSModel`: A compiled BUGS model

# Returns
- An `OfNamedTuple` type representing the structure of all variables in the model

# Example
```julia
# Define and compile a model
@model function regression((; y, beta, sigma), X, N)
    # ... model definition ...
end

model = regression((; y = data), X, N)

# Extract the of type from the compiled model
ModelType = of(model)
# ModelType might be: @of(y = of(Array, Float64, 100), beta = of(Array, Float64, 3), sigma = of(Real, 0, nothing))

# Use the extracted type
rand(ModelType)  # Generate random values matching the model structure
```
"""
of(model::BUGSModel) = of(model.evaluation_env)

include("model_macro.jl")

export of

include("serialization.jl")

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
