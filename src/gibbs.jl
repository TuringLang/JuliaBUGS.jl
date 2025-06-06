struct Gibbs{N,S} <: AbstractMCMC.AbstractSampler
    sampler_map::OrderedDict{N,S}
    
    function Gibbs{N,S}(sampler_map::OrderedDict{N,S}) where {N,S}
        new{N,S}(sampler_map)
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
        expanded_sampler_map[expanded_vars] = sampler
    end
    return Gibbs{eltype(keys(expanded_sampler_map)), eltype(values(expanded_sampler_map))}(expanded_sampler_map)
end

# Simple constructor for using same sampler for all parameters
function Gibbs(model::BUGSModel, s::AbstractMCMC.AbstractSampler)
    sampler_map = OrderedDict([v => s for v in model.graph_evaluation_data.sorted_parameters])
    return Gibbs(model, sampler_map)
end

abstract type AbstractGibbsState end

struct GibbsState{E<:NamedTuple,S,C} <: AbstractGibbsState
    evaluation_env::E
    conditioning_schedule::S
    cached_conditioned_models::C
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
                throw(ArgumentError(
                    "Variable $var is covered multiple times in the sampler map"
                ))
            end
            push!(covered_parameters, var)
        else
            # Check for subsuming behavior
            subsumed = filter(p -> AbstractPPL.subsumes(var, p), model_parameters)
            if isempty(subsumed)
                throw(ArgumentError(
                    "Sampler map contains variable not in the model: $var"
                ))
            end
            # Add all subsumed parameters
            for p in subsumed
                if p in covered_parameters
                    throw(ArgumentError(
                        "Variable $p is covered multiple times in the sampler map (subsumed by $var)"
                    ))
                end
                push!(covered_parameters, p)
            end
        end
    end
    
    # Check for missing variables
    missing_variables = setdiff(Set(model_parameters), covered_parameters)
    if !isempty(missing_variables)
        throw(ArgumentError(
            "Some model parameters are not covered by the sampler map: $(collect(missing_variables))"
        ))
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
    
    cached_conditioned_models, conditioning_schedule = OrderedDict(), OrderedDict()
    model_parameters = model.graph_evaluation_data.sorted_parameters
    
    for variables_to_update in keys(sampler.sampler_map)
        # Variables to condition on are all parameters except those we're updating
        variables_to_condition_on = setdiff(model_parameters, variables_to_update)

        conditioning_schedule[variables_to_update] = sampler.sampler_map[variables_to_update]

        # Create conditioned model
        conditioned_model = AbstractPPL.condition(
            model, variables_to_condition_on
        )
        cached_conditioned_models[variables_to_update] = conditioned_model
    end
    return model.evaluation_env, GibbsState(model.evaluation_env, conditioning_schedule, cached_conditioned_models)
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
    for variables_to_update in keys(state.conditioning_schedule)
        # Update model with current evaluation environment
        model = BangBang.setproperty!!(model, :evaluation_env, evaluation_env)
        
        # Retrieve cached conditioned model and update its evaluation environment
        cond_model = BangBang.setproperty!!(
            state.cached_conditioned_models[variables_to_update],
            :evaluation_env,
            evaluation_env
        )
        
        # gibbs_internal now returns param_values, need to update evaluation_env
        param_values = gibbs_internal(rng, cond_model, state.conditioning_schedule[variables_to_update])
        
        # Update evaluation_env by setting model with new param values
        model_updated = initialize!(model, param_values)
        evaluation_env = model_updated.evaluation_env
    end
    return evaluation_env,
    GibbsState(evaluation_env, state.conditioning_schedule, state.cached_conditioned_models)
end

function gibbs_internal end
