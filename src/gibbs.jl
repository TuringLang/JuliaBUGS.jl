"""
    WithGradient(sampler, ad_backend=AutoReverseDiff())

Wrapper for gradient-based samplers (HMC, NUTS) that specifies which automatic
differentiation backend to use.

This wrapper allows users to explicitly choose the AD backend for gradient computations
in samplers that require gradients. It's particularly useful when different AD backends
have different performance characteristics for specific models.

# Arguments
- `sampler`: The base sampler (e.g., HMC, NUTS from AdvancedHMC)
- `ad_backend`: AD backend from ADTypes (e.g., `AutoReverseDiff()`, `AutoForwardDiff()`, `AutoMooncake()`)

# Supported AD Backends
- `AutoReverseDiff()` (default): Good for models with many parameters
- `AutoForwardDiff()`: Good for models with few parameters (<100)
- `AutoMooncake()`: Experimental, potentially faster for some models. Note: When using `UseGeneratedLogDensityFunction()` evaluation mode, only `AutoMooncake()` is supported for AD

# Examples
```jldoctest
julia> using JuliaBUGS: WithGradient, IndependentMH

julia> using ADTypes

julia> # Explicit AD specification
       WithGradient(IndependentMH(), AutoForwardDiff())
WithGradient{IndependentMH, AutoForwardDiff{nothing, Nothing}}(IndependentMH(), AutoForwardDiff())

julia> # Default to ReverseDiff
       WithGradient(IndependentMH())
WithGradient{IndependentMH, AutoReverseDiff{false}}(IndependentMH(), AutoReverseDiff())
```

For use with HMC/NUTS samplers (requires AdvancedHMC):
```julia
WithGradient(HMC(0.01, 10), AutoForwardDiff())
WithGradient(NUTS(0.65), AutoMooncake())

# Use in Gibbs sampling
sampler_map = OrderedDict(
    @varname(μ) => WithGradient(HMC(0.01, 10), AutoForwardDiff()),
    @varname(σ) => WithGradient(NUTS(0.65), AutoReverseDiff())
)
```
"""
struct WithGradient{S<:AbstractMCMC.AbstractSampler,AD<:ADTypes.AbstractADType}
    sampler::S
    ad_backend::AD
end

# Default to ReverseDiff
WithGradient(sampler) = WithGradient(sampler, ADTypes.AutoReverseDiff())

"""
    Gibbs{N,S} <: AbstractMCMC.AbstractSampler

Gibbs sampler that updates different groups of parameters using different samplers.

The Gibbs sampler divides model parameters into groups and updates each group
sequentially using potentially different sampling algorithms. This is particularly
useful for models where different parameters have different properties (e.g., 
continuous vs discrete, or different dimensionalities).

# Type Parameters
- `N`: Type of the variable groups (usually vectors of `VarName`)
- `S`: Type of the samplers

# Fields
- `sampler_map::OrderedDict{N,S}`: Maps variable groups to their respective samplers

# See Also
- [`WithGradient`](@ref): For specifying AD backends for gradient-based samplers
- [`IndependentMH`](@ref): A simple Metropolis-Hastings sampler
"""
struct Gibbs{N,S} <: AbstractMCMC.AbstractSampler
    sampler_map::OrderedDict{N,S}

    function Gibbs{N,S}(sampler_map::OrderedDict{N,S}) where {N,S}
        return new{N,S}(sampler_map)
    end
end

"""
    update_sampler_state(model::BUGSModel, sampler, state)

Update the sampler state to reflect parameter changes from other samplers in Gibbs.

When using Gibbs sampling, parameters updated by one sampler affect the log density
and gradients used by other samplers. This function updates the sampler's internal
state to reflect these changes.

# Arguments
- `model`: The current conditioned BUGSModel
- `sampler`: The sampler whose state needs updating
- `state`: The current state of the sampler

# Returns
- Updated sampler state

# Implementation Notes
This is a generic fallback that returns the state unchanged. Extensions should
override this method for samplers that maintain internal state (e.g., HMC/NUTS
with cached gradients).
```
"""
function update_sampler_state(model::BUGSModel, sampler, state)
    # Default: return state unchanged
    # Extensions should override this for their sampler types
    return state
end

"""
    ensure_explicit_ad_backend(sampler)

Ensure gradient-based samplers have an explicit AD backend specification.

This internal helper function checks if a sampler requires gradients (HMC, NUTS)
and wraps it with `WithGradient` if not already wrapped. This ensures all
gradient-based samplers have an explicit AD backend, defaulting to ReverseDiff.

# Arguments
- `sampler`: Any AbstractMCMC sampler

# Returns
- The sampler wrapped in `WithGradient` if it's gradient-based and not already wrapped
- The original sampler otherwise

# Notes
This function uses heuristics (type name matching) to detect gradient-based samplers.
Users should prefer explicitly wrapping their samplers with `WithGradient` for clarity.
"""
function ensure_explicit_ad_backend(sampler)
    # If already wrapped, return as-is
    if sampler isa WithGradient
        return sampler
    end

    # Check if it's a gradient-based sampler by checking if module is loaded
    # and sampler type name suggests it needs gradients
    sampler_type = string(typeof(sampler))
    if (occursin("HMC", sampler_type) || occursin("NUTS", sampler_type)) &&
        occursin("AdvancedHMC", sampler_type)
        # Wrap with default AD backend
        # Note: Users should prefer explicit WithGradient(sampler, AutoReverseDiff())
        return WithGradient(sampler, ADTypes.AutoReverseDiff())
    else
        # Return as-is for other samplers
        return sampler
    end
end

"""
    Gibbs(model::BUGSModel, sampler_map::OrderedDict)

Construct a Gibbs sampler with different samplers for different parameter groups.

This constructor creates a Gibbs sampler that updates different groups of parameters
using potentially different sampling algorithms. It automatically handles variable
expansion for array parameters and ensures gradient-based samplers have explicit
AD backends.

# Arguments
- `model`: The BUGSModel to sample from
- `sampler_map`: An OrderedDict mapping variable groups to samplers

# Variable Grouping
Variables can be specified individually or as groups:
- Single variable: `@varname(α) => sampler`
- Multiple variables: `[@varname(α), @varname(β)] => sampler`
- Array variables: `@varname(x)` automatically expands to include all `x[i]`

# Examples
```julia
# Different samplers for different parameters
sampler_map = OrderedDict(
    @varname(μ) => WithGradient(HMC(0.01, 10)),
    @varname(σ) => WithGradient(NUTS(0.65)),
    @varname(k) => IndependentMH()  # Good for discrete parameters
)
gibbs = Gibbs(model, sampler_map)

# Group parameters that should be updated together
sampler_map = OrderedDict(
    [@varname(α), @varname(β)] => WithGradient(HMC(0.01, 10)),
    @varname(σ) => WithGradient(NUTS(0.65))
)
gibbs = Gibbs(model, sampler_map)

# Array variables are automatically expanded
sampler_map = OrderedDict(
    @varname(x) => IndependentMH(),  # Updates all x[1], x[2], ..., x[n]
    @varname(μ) => WithGradient(HMC(0.01, 10))
)
gibbs = Gibbs(model, sampler_map)
```

# Throws
- `ArgumentError`: If sampler map doesn't cover all model parameters exactly once
"""
function Gibbs(model::BUGSModel, sampler_map::OrderedDict)
    verify_sampler_map(model, sampler_map)
    # Expand variable groups once to avoid repeated computation
    model_parameters = model.graph_evaluation_data.sorted_parameters
    expanded_sampler_map = OrderedDict()
    for (variable_group, sampler) in sampler_map
        variable_group_vec =
            (variable_group isa VarName) ? [variable_group] : variable_group
        expanded_vars = expand_variables(variable_group_vec, model_parameters)
        # Ensure gradient-based samplers have explicit AD backend
        wrapped_sampler = ensure_explicit_ad_backend(sampler)
        expanded_sampler_map[expanded_vars] = wrapped_sampler
    end
    return Gibbs{eltype(keys(expanded_sampler_map)),eltype(values(expanded_sampler_map))}(
        expanded_sampler_map
    )
end

"""
    Gibbs(model::BUGSModel, sampler::AbstractMCMC.AbstractSampler)

Construct a Gibbs sampler using the same sampler for all parameters.

This convenience constructor creates a Gibbs sampler that updates each parameter
individually using the same sampling algorithm. This is equivalent to standard
single-site Gibbs sampling.

# Arguments
- `model`: The BUGSModel to sample from
- `sampler`: The sampler to use for all parameters

# Examples
```julia
# Use IndependentMH for all parameters
gibbs = Gibbs(model, IndependentMH())

# Use HMC for all parameters (each updated individually)
gibbs = Gibbs(model, WithGradient(HMC(0.01, 10)))
```

# Notes
For better performance with continuous parameters, consider grouping related
parameters and using the OrderedDict constructor instead.
"""
function Gibbs(model::BUGSModel, s::AbstractMCMC.AbstractSampler)
    # Ensure gradient-based samplers have explicit AD backend
    wrapped_sampler = ensure_explicit_ad_backend(s)
    sampler_map = OrderedDict([
        v => wrapped_sampler for v in model.graph_evaluation_data.sorted_parameters
    ])
    return Gibbs(model, sampler_map)
end

"""
    AbstractGibbsState

Abstract type for Gibbs sampler states.

This serves as the base type for all Gibbs sampler state implementations,
allowing for future extensions and alternative state representations.
"""
abstract type AbstractGibbsState end

"""
    GibbsState{E<:NamedTuple,C,T} <: AbstractGibbsState

State for the Gibbs sampler containing current values and cached information.

# Type Parameters
- `E<:NamedTuple`: Type of the evaluation environment
- `C`: Type of the cached conditioned models dictionary
- `T`: Type of the sub-states dictionary

# Fields
- `evaluation_env::E`: Current values of all variables in the model
- `cached_conditioned_models::C`: Pre-computed conditioned models for each parameter group
- `sub_states::T`: States from sub-samplers (e.g., adaptation state for HMC/NUTS)

# Notes
The evaluation environment contains the current values of all variables (parameters,
data, and deterministic nodes). The cached conditioned models avoid recomputing
the conditioning at each iteration. Sub-states allow stateful samplers like HMC
to maintain their adaptation information across Gibbs iterations.
"""
struct GibbsState{E<:NamedTuple,C,T} <: AbstractGibbsState
    evaluation_env::E
    cached_conditioned_models::C
    sub_states::T  # States from sub-samplers (HMC, NUTS, etc.)
end

"""
    expand_variables(vars::Vector{<:VarName}, model_parameters::Vector{<:VarName})

Expand variables to include all subsumed parameters from the model.

This function handles the subsuming relationship between variables. When a variable
like `x` is specified, it expands to include all indexed versions like `x[1]`, `x[2]`, etc.
that exist in the model parameters.

# Arguments
- `vars`: Vector of variables to expand
- `model_parameters`: All parameters in the model

# Returns
- Vector of expanded variables with duplicates removed

# Examples
```jldoctest
julia> using JuliaBUGS: expand_variables, @varname

julia> model_parameters = [@varname(x[1]), @varname(x[2]), @varname(x[3]), @varname(y)];

julia> expand_variables([@varname(x)], model_parameters)
3-element Vector{AbstractPPL.VarName}:
 x[1]
 x[2]
 x[3]

julia> expand_variables([@varname(x[1]), @varname(y)], model_parameters)
2-element Vector{AbstractPPL.VarName}:
 x[1]
 y
```
"""
function expand_variables(vars::Vector{<:VarName}, model_parameters::Vector{<:VarName})
    expanded = VarName[]
    for var in vars
        # Check if var is directly in model parameters
        if var in model_parameters
            push!(expanded, var)
        else
            # Find all parameters subsumed by var
            subsumed = filter(p -> AbstractPPL.subsumes(var, p), model_parameters)
            append!(expanded, subsumed)
        end
    end
    return unique(expanded)
end

"""
    verify_sampler_map(model::BUGSModel, sampler_map::OrderedDict)

Verify that the sampler map covers all model parameters exactly once, handling subsuming relationships.

# Arguments
- `model`: The BUGSModel to verify against
- `sampler_map`: OrderedDict mapping variable groups to samplers

# Throws
- `ArgumentError` if sampler map contains extra variables not in model
- `ArgumentError` if some model parameters are not covered by sampler map

# Subsuming Behavior
When a variable like `x` subsumes indexed variables like `x[1]`, `x[2]`, the verification
handles this correctly. For example, if the model has `x[1]`, `x[2]`, `x[3]` as parameters,
specifying just `x` in the sampler map will cover all of them.

# Examples
```julia
model = compile(...)
# Case 1: Individual variables
sampler_map = OrderedDict(
    [@varname(α)] => IndependentMH(),
    [@varname(β), @varname(γ)] => HMC(0.01, 10)
)

# Case 2: Subsuming - x covers x[1], x[2], etc.
sampler_map = OrderedDict(
    [@varname(x)] => IndependentMH(),  # Covers all x[i]
    [@varname(β)] => HMC(0.01, 10)
)
verify_sampler_map(model, sampler_map)  # Throws if invalid
```
"""
function verify_sampler_map(model::BUGSModel, sampler_map::OrderedDict)
    # Collect all variables from sampler map keys
    all_variables_in_keys = VarName[]
    for variable_group in keys(sampler_map)
        variable_group_vec =
            (variable_group isa VarName) ? [variable_group] : variable_group
        append!(all_variables_in_keys, variable_group_vec)
    end

    # Get model parameters
    model_parameters = model.graph_evaluation_data.sorted_parameters

    # Track which model parameters are covered
    covered_parameters = Set{VarName}()

    # For each variable in sampler map, find which model parameters it covers
    for var in all_variables_in_keys
        # Check if this variable exists in model parameters directly
        if var in model_parameters
            if var in covered_parameters
                throw(
                    ArgumentError(
                        "Variable $var is covered multiple times in the sampler map"
                    ),
                )
            end
            push!(covered_parameters, var)
        else
            # Check for subsuming behavior
            subsumed = filter(p -> AbstractPPL.subsumes(var, p), model_parameters)
            if isempty(subsumed)
                throw(ArgumentError("Sampler map contains variable not in the model: $var"))
            end
            # Add all subsumed parameters
            for p in subsumed
                if p in covered_parameters
                    throw(
                        ArgumentError(
                            "Variable $p is covered multiple times in the sampler map (subsumed by $var)",
                        ),
                    )
                end
                push!(covered_parameters, p)
            end
        end
    end

    # Check for missing variables
    missing_variables = setdiff(Set(model_parameters), covered_parameters)
    if !isempty(missing_variables)
        throw(
            ArgumentError(
                "Some model parameters are not covered by the sampler map: $(collect(missing_variables))",
            ),
        )
    end

    return true
end

"""
Initial step of the Gibbs sampler.

This function initializes the Gibbs sampler by:
1. Verifying the sampler map covers all parameters
2. Creating conditioned models for each parameter group
3. Initializing the sampler state

# Returns
- `evaluation_env`: Current values of all variables
- `state`: Initial GibbsState with cached conditioned models
"""
function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs{N,S};
    model=l_model.logdensity,
    kwargs...,
) where {N,S}
    # Verify sampler map on first step
    verify_sampler_map(model, sampler.sampler_map)

    cached_conditioned_models = OrderedDict()
    model_parameters = model.graph_evaluation_data.sorted_parameters

    for variables_to_update in keys(sampler.sampler_map)
        # Variables to condition on are all parameters except those we're updating
        variables_to_condition_on = setdiff(model_parameters, variables_to_update)

        # Create conditioned model
        conditioned_model = AbstractPPL.condition(model, variables_to_condition_on)
        cached_conditioned_models[variables_to_update] = conditioned_model
    end
    # Initialize sub_states as empty Dict
    sub_states = Dict{Any,Any}()
    return model.evaluation_env,
    GibbsState(model.evaluation_env, cached_conditioned_models, sub_states)
end

"""
Perform one iteration of the Gibbs sampler.

This function updates each parameter group sequentially using its assigned sampler.
For each group:
1. The conditioned model is updated with current values
2. The sub-sampler state is updated if necessary (for stateful samplers)
3. The sub-sampler takes a step to update the parameters
4. The new state is stored for future iterations

# Arguments
- `rng`: Random number generator
- `l_model`: Log density model wrapper
- `sampler`: The Gibbs sampler
- `state`: Current state containing values and cached models

# Returns
- `evaluation_env`: Updated values of all variables
- `state`: Updated GibbsState with new values and sub-states
"""
function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs,
    state::AbstractGibbsState;
    model=l_model.logdensity,
    kwargs...,
)
    evaluation_env = state.evaluation_env
    for variables_to_update in keys(state.cached_conditioned_models)
        # Update model with current evaluation environment
        model = BangBang.setproperty!!(model, :evaluation_env, evaluation_env)

        # Retrieve cached conditioned model and update its evaluation environment
        cond_model = BangBang.setproperty!!(
            state.cached_conditioned_models[variables_to_update],
            :evaluation_env,
            evaluation_env,
        )

        # gibbs_internal returns the updated evaluation_env and optional sampler state
        sub_sampler = sampler.sampler_map[variables_to_update]

        # Get the sub-state for this sampler (if it exists)
        sub_state = get(state.sub_states, variables_to_update, nothing)

        # Update the state to reflect changes from other samplers
        if !isnothing(sub_state)
            # Update state for any sampler type to account for parameter changes
            sub_state = update_sampler_state(cond_model, sub_sampler, sub_state)
        end

        # Take a step with the sampler
        # gibbs_internal is implemented by each sampler type (IndependentMH, HMC extensions, etc.)
        # It returns the updated evaluation_env and optional sampler state
        evaluation_env, new_sub_state = gibbs_internal(
            rng, cond_model, sub_sampler, sub_state
        )

        # Store the new sub-state if returned
        if !isnothing(new_sub_state)
            state.sub_states[variables_to_update] = new_sub_state
        end
    end
    return evaluation_env,
    GibbsState(evaluation_env, state.cached_conditioned_models, state.sub_states)
end
