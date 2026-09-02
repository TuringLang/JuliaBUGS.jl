# Gradient-based Samplers with AD Backends
#
# For gradient-based samplers (HMC, NUTS), specify the AD backend using a tuple:
# `(sampler, ad_backend)` where `ad_backend` is from ADTypes.
#
# Supported AD Backends:
# - `AutoMooncake()`: Recommended native reverse-mode backend
# - `AutoReverseDiff()`: DI-backed reverse mode
# - `AutoForwardDiff()`: DI-backed forward mode for small models (<100 parameters)
#
# Examples:
# ```julia
# using ADTypes, Mooncake
# 
# # Explicit AD specification
# sampler_map = OrderedDict(
#     @varname(μ) => (HMC(0.01, 10), AutoMooncake()),
#     @varname(σ) => (NUTS(0.65), AutoMooncake())
# )
# 
# # For gradient-based samplers, always specify AD backend
# sampler_map = OrderedDict(
#     @varname(μ) => (HMC(0.01, 10), AutoMooncake()),
#     @varname(σ) => (NUTS(0.65), AutoMooncake())
# )
# ```

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
- `AdvancedMH`: Metropolis-Hastings samplers
- Gradient-based samplers: Use tuples `(sampler, ad_backend)` to specify AD backends
"""
struct Gibbs{N,S} <: AbstractMCMC.AbstractSampler
    sampler_map::OrderedDict{N,S}

    function Gibbs{N,S}(sampler_map::OrderedDict{N,S}) where {N,S}
        return new{N,S}(sampler_map)
    end
end

"""
    EnumeratedSampler()

Update a finite discrete Gibbs block exactly from its full conditional distribution.

`Gibbs` selects this kernel automatically when every variable in a block has finite
discrete support. Specify it explicitly in a sampler map to make that choice visible.
"""
struct EnumeratedSampler <: AbstractMCMC.AbstractSampler end

validate_gibbs_component(::BUGSModel, _variables, _sampler) = nothing

function _gibbs_component_node_types(model::BUGSModel, variables)
    node_types = Model._compute_node_types(model)
    sorted_nodes = model.graph_evaluation_data.sorted_nodes
    return map(variables) do variable
        return node_types[findfirst(==(variable), sorted_nodes)]
    end
end

function _select_gibbs_component_sampler(model::BUGSModel, variables, sampler)
    node_types = _gibbs_component_node_types(model, variables)
    finite_discrete = node_types .=== :discrete_finite
    if all(finite_discrete)
        return EnumeratedSampler()
    elseif any(finite_discrete)
        throw(
            ArgumentError(
                "Finite discrete variables must form a separate Gibbs block so that " *
                "they can be sampled exactly from their full conditional.",
            ),
        )
    elseif sampler isa EnumeratedSampler
        throw(ArgumentError("EnumeratedSampler requires a finite discrete Gibbs block."))
    end
    return sampler
end

function _require_continuous_gibbs_component(model::BUGSModel, variables, sampler_name)
    node_types = _gibbs_component_node_types(model, variables)
    discrete_variables = [
        variable for (variable, node_type) in zip(variables, node_types) if
        node_type === :discrete_finite || node_type === :discrete_infinite
    ]
    isempty(discrete_variables) || throw(
        ArgumentError(
            "$sampler_name cannot update discrete Gibbs variables: " *
            join(discrete_variables, ", ") *
            ". Use AdvancedMH with a discrete proposal.",
        ),
    )
    return nothing
end

"""
    Gibbs(model::BUGSModel, sampler_map::OrderedDict)

Construct a Gibbs sampler with different samplers for different parameter groups.

This constructor creates a Gibbs sampler that updates different groups of parameters
using potentially different sampling algorithms. It automatically handles variable
expansion for array parameters and ensures gradient-based samplers have explicit
AD backends. A block consisting only of finite discrete variables is always updated
exactly with `EnumeratedSampler`, irrespective of the sampler supplied for that block.

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
using ADTypes: AutoMooncake, AutoReverseDiff, AutoForwardDiff
using Mooncake
using DifferentiationInterface, ReverseDiff, ForwardDiff

# Different samplers for different parameters
sampler_map = OrderedDict(
    @varname(μ) => (HMC(0.01, 10), AutoMooncake()),
    @varname(σ) => (NUTS(0.65), AutoMooncake()),
    @varname(k) => EnumeratedSampler()
)
gibbs = Gibbs(model, sampler_map)

# Group parameters that should be updated together
sampler_map = OrderedDict(
    [@varname(α), @varname(β)] => (HMC(0.01, 10), AutoForwardDiff()),
    @varname(σ) => (NUTS(0.65), AutoForwardDiff())  # Must specify AD backend
)
gibbs = Gibbs(model, sampler_map)

# Array variables are automatically expanded
sampler_map = OrderedDict(
    @varname(x) => RWMH(MvNormal(zeros(n), 0.1 * I)),
    @varname(μ) => (HMC(0.01, 10), AutoForwardDiff())  # Must specify AD backend
)
gibbs = Gibbs(model, sampler_map)
```

# Throws
- `ArgumentError`: If sampler map doesn't cover all model parameters exactly once
"""
function Gibbs(model::BUGSModel, sampler_map::OrderedDict)
    verify_sampler_map(model, sampler_map)
    # Expand variable groups once to avoid repeated computation
    model_parameters = model.graph_evaluation_data.model_parameters
    expanded_sampler_map = OrderedDict()
    for (variable_group, sampler) in sampler_map
        variable_group_vec =
            (variable_group isa VarName) ? [variable_group] : variable_group
        expanded_vars = expand_variables(variable_group_vec, model_parameters)
        selected_sampler = _select_gibbs_component_sampler(model, expanded_vars, sampler)
        validate_gibbs_component(model, expanded_vars, selected_sampler)
        expanded_sampler_map[expanded_vars] = selected_sampler
    end
    return Gibbs{eltype(keys(expanded_sampler_map)),eltype(values(expanded_sampler_map))}(
        expanded_sampler_map
    )
end

"""
    Gibbs(model::BUGSModel, sampler)

Construct a Gibbs sampler using the same sampler for all parameters.

This convenience constructor creates a Gibbs sampler that updates each parameter
individually using the same sampling algorithm. This is equivalent to standard
single-site Gibbs sampling.

# Arguments
- `model`: The BUGSModel to sample from
- `sampler`: The sampler to use for all parameters

# Examples
```julia
using ADTypes: AutoMooncake
using Mooncake

# Use random-walk MH for all scalar parameters
gibbs = Gibbs(model, RWMH([Normal(0, 0.1)]))

# Use HMC for all parameters (each updated individually)
gibbs = Gibbs(model, (HMC(0.01, 10), AutoMooncake()))
# Note: For gradient-based samplers, you must specify the AD backend
```

# Notes
For better performance with continuous parameters, consider grouping related
parameters and using the OrderedDict constructor instead.
"""
function Gibbs(
    model::BUGSModel,
    sampler::Union{
        AbstractMCMC.AbstractSampler,
        Tuple{<:AbstractMCMC.AbstractSampler,<:ADTypes.AbstractADType},
    },
)
    sampler_map = OrderedDict([
        variable => sampler for variable in model.graph_evaluation_data.model_parameters
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

function gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, ::EnumeratedSampler, _state=nothing
)
    evaluation_env = Model.smart_copy_evaluation_env(
        cond_model.evaluation_env, cond_model.mutable_symbols
    )
    evaluation_env = Model._sample_discrete_latents!!(rng, cond_model, evaluation_env)
    return evaluation_env, nothing
end

# MH and slice initialization does not move; a Gibbs sweep must advance the block.
function _step_gibbs_component_after_initialization(
    rng::Random.AbstractRNG,
    logdensitymodel::AbstractMCMC.LogDensityModel,
    sampler,
    state;
    initial_params,
    kwargs...,
)
    if isnothing(state)
        _, state = AbstractMCMC.step(
            rng, logdensitymodel, sampler; initial_params, kwargs...
        )
    end
    return AbstractMCMC.step(rng, logdensitymodel, sampler, state; kwargs...)
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
3-element Vector{VarName}:
 x[1]
 x[2]
 x[3]

julia> expand_variables([@varname(x[1]), @varname(y)], model_parameters)
2-element Vector{VarName}:
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
    [@varname(α)] => RWMH([Normal(0, 0.1)]),
    [@varname(β), @varname(γ)] => HMC(0.01, 10)
)

# Case 2: Subsuming - x covers x[1], x[2], etc.
sampler_map = OrderedDict(
    [@varname(x)] => RWMH(MvNormal(zeros(n), 0.1 * I)),
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
    model_parameters = model.graph_evaluation_data.model_parameters

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
    l_model::AbstractMCMC.LogDensityModel{<:Model.BUGSModelLike},
    sampler::Gibbs{N,S};
    model=Model.base_bugs_model(l_model),
    kwargs...,
) where {N,S}
    verify_sampler_map(model, sampler.sampler_map)

    cached_conditioned_models = OrderedDict()
    model_parameters = model.graph_evaluation_data.model_parameters

    for variables_to_update in keys(sampler.sampler_map)
        variables_to_condition_on = setdiff(model_parameters, variables_to_update)
        conditioned_model = AbstractPPL.condition(model, variables_to_condition_on)
        if sampler.sampler_map[variables_to_update] isa EnumeratedSampler
            # Marginalization requires transformed mode; exact blocks are entirely discrete.
            conditioned_model = settrans(conditioned_model, true)
            conditioned_model = set_evaluation_mode(
                conditioned_model, UseAutoMarginalization()
            )
            conditioned_model.evaluation_mode isa UseAutoMarginalization || error(
                "Could not construct the exact conditional for finite discrete Gibbs block " *
                "$(variables_to_update).",
            )
        end
        cached_conditioned_models[variables_to_update] = conditioned_model
    end
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
    l_model::AbstractMCMC.LogDensityModel{<:Model.BUGSModelLike},
    sampler::Gibbs,
    state::AbstractGibbsState;
    model=Model.base_bugs_model(l_model),
    kwargs...,
)
    evaluation_env = state.evaluation_env
    for variables_to_update in keys(state.cached_conditioned_models)
        cond_model = BangBang.setproperty!!(
            state.cached_conditioned_models[variables_to_update],
            :evaluation_env,
            evaluation_env,
        )

        sub_sampler = sampler.sampler_map[variables_to_update]
        sub_state = get(state.sub_states, variables_to_update, nothing)

        if !isnothing(sub_state)
            θ_new = getparams(cond_model)

            if sub_sampler isa
                Tuple{<:AbstractMCMC.AbstractSampler,<:ADTypes.AbstractADType}
                _, ad_backend = sub_sampler
                logdensitymodel = AbstractMCMC.LogDensityModel(
                    Model.BUGSModelWithGradient(cond_model, ad_backend)
                )
            else
                logdensitymodel = AbstractMCMC.LogDensityModel(cond_model)
            end

            sub_state = AbstractMCMC.setparams!!(logdensitymodel, sub_state, θ_new)
        end

        evaluation_env, new_sub_state = gibbs_internal(
            rng, cond_model, sub_sampler, sub_state
        )

        if !isnothing(new_sub_state)
            state.sub_states[variables_to_update] = new_sub_state
        end
    end
    return evaluation_env,
    GibbsState(evaluation_env, state.cached_conditioned_models, state.sub_states)
end

# The component samplers keep their own statistics, which `Gibbs` does not aggregate.
function transition_params_and_stats(::BUGSModel, ::Gibbs, evaluation_env::NamedTuple)
    return evaluation_env, NamedTuple()
end
