"""
    WithGradient(sampler, ad_backend=:ReverseDiff)

Wrapper for gradient-based samplers (HMC, NUTS) that specifies which automatic
differentiation backend to use.

# Arguments
- `sampler`: The base sampler (e.g., HMC, NUTS from AdvancedHMC)
- `ad_backend`: AD backend to use (`:ReverseDiff`, `:ForwardDiff`, `:Zygote`, etc.)

# Examples
```julia
# Explicit AD specification
WithGradient(HMC(0.01, 10), :ForwardDiff)
WithGradient(NUTS(0.65), :Zygote)

# Default to ReverseDiff
WithGradient(HMC(0.01, 10))
```
"""
struct WithGradient{S<:AbstractMCMC.AbstractSampler,AD}
    sampler::S
    ad_backend::AD
end

# Default to ReverseDiff
WithGradient(sampler) = WithGradient(sampler, :ReverseDiff)

struct Gibbs{N,S} <: AbstractMCMC.AbstractSampler
    sampler_map::OrderedDict{N,S}

    function Gibbs{N,S}(sampler_map::OrderedDict{N,S}) where {N,S}
        return new{N,S}(sampler_map)
    end
end

# Helper to ensure gradient-based samplers have explicit AD backend
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
        # Note: Users should prefer explicit WithGradient(sampler, :ReverseDiff)
        return WithGradient(sampler, :ReverseDiff)
    else
        # Return as-is for other samplers
        return sampler
    end
end

# Constructor with verification and variable expansion for convenience
function Gibbs(model::BUGSModel, sampler_map::OrderedDict)
    verify_sampler_map(model, sampler_map)
    # Expand variable groups once to avoid repeated computation
    model_parameters = model.graph_evaluation_data.sorted_parameters
    expanded_sampler_map = OrderedDict()
    for (variable_group, sampler) in sampler_map
        expanded_vars = expand_variables(ensure_vector(variable_group), model_parameters)
        # Ensure gradient-based samplers have explicit AD backend
        wrapped_sampler = ensure_explicit_ad_backend(sampler)
        expanded_sampler_map[expanded_vars] = wrapped_sampler
    end
    return Gibbs{eltype(keys(expanded_sampler_map)),eltype(values(expanded_sampler_map))}(
        expanded_sampler_map
    )
end

# Simple constructor for using same sampler for all parameters
function Gibbs(model::BUGSModel, s::AbstractMCMC.AbstractSampler)
    # Ensure gradient-based samplers have explicit AD backend
    wrapped_sampler = ensure_explicit_ad_backend(s)
    sampler_map = OrderedDict([
        v => wrapped_sampler for v in model.graph_evaluation_data.sorted_parameters
    ])
    return Gibbs(model, sampler_map)
end

abstract type AbstractGibbsState end

struct GibbsState{E<:NamedTuple,C,T} <: AbstractGibbsState
    evaluation_env::E
    cached_conditioned_models::C
    sub_states::T  # States from sub-samplers (HMC, NUTS, etc.)
end

ensure_vector(x) = x isa Union{Number,VarName} ? [x] : x

"""
    expand_variables(vars::Vector{<:VarName}, model_parameters::Vector{<:VarName})

Expand variables to include all subsumed parameters from the model.

For example, if `vars = [x]` and `model_parameters = [x[1], x[2], x[3], y]`,
returns `[x[1], x[2], x[3]]`.
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
    [@varname(α)] => MHFromPrior(),
    [@varname(β), @varname(γ)] => HMC(0.01, 10)
)

# Case 2: Subsuming - x covers x[1], x[2], etc.
sampler_map = OrderedDict(
    [@varname(x)] => MHFromPrior(),  # Covers all x[i]
    [@varname(β)] => HMC(0.01, 10)
)
verify_sampler_map(model, sampler_map)  # Throws if invalid
```
"""
function verify_sampler_map(model::BUGSModel, sampler_map::OrderedDict)
    # Collect all variables from sampler map keys
    all_variables_in_keys = VarName[]
    for variable_group in keys(sampler_map)
        append!(all_variables_in_keys, ensure_vector(variable_group))
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
        # For gradient-based samplers (HMC/NUTS), we don't preserve state across iterations
        # because the adaptation information becomes stale when the conditional distribution changes
        sub_sampler = sampler.sampler_map[variables_to_update]
        if sub_sampler isa WithGradient
            # Always pass nothing as state for gradient-based samplers
            evaluation_env, _ = gibbs_internal(rng, cond_model, sub_sampler, nothing)
        else
            # For other samplers (like MHFromPrior), preserve state if beneficial
            sub_state = get(state.sub_states, variables_to_update, nothing)
            evaluation_env, new_sub_state = gibbs_internal(
                rng, cond_model, sub_sampler, sub_state
            )
            # Store the new sub-state if returned
            if !isnothing(new_sub_state)
                state.sub_states[variables_to_update] = new_sub_state
            end
        end
    end
    return evaluation_env,
    GibbsState(evaluation_env, state.cached_conditioned_models, state.sub_states)
end
