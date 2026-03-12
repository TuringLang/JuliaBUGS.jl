using Serialization

# Serialize BUGSModel by writing minimal reconstruction state only.
function Serialization.serialize(s::Serialization.AbstractSerializer, model::BUGSModel)
    if !isnothing(model.base_model)
        throw(ArgumentError("Conditioned model can't be serialized."))
    end

    Serialization.writetag(s.io, Serialization.OBJECT_TAG)
    # Write unparameterized type to avoid embedding typeOf(model)
    Serialization.serialize(s, BUGSModel)

    # Serialize minimal state; skip generated functions and caches
    Serialization.serialize(s, (
        transformed = model.transformed,
        model_def = model.model_def,
        data = model.data,
        evaluation_env = model.evaluation_env,
        evaluation_mode = model.evaluation_mode
    ))
    return nothing
end

# Serialize BUGSModelWithGradient by storing the AD type and base model.
function Serialization.serialize(
    s::Serialization.AbstractSerializer,
    gw::JuliaBUGS.Model.BUGSModelWithGradient,
)
    Serialization.writetag(s.io, Serialization.OBJECT_TAG)
    Serialization.serialize(s, JuliaBUGS.Model.BUGSModelWithGradient)
    Serialization.serialize(s, (adtype = gw.adtype, base_model = gw.base_model))
    return nothing
end

# Deserialize `BUGSModelWithGradient` and rebuild the gradient wrapper locally.
function Serialization.deserialize(
    s::Serialization.AbstractSerializer,
    ::Type{<:JuliaBUGS.Model.BUGSModelWithGradient},
)
    state = Serialization.deserialize(s)
    base_model = state.base_model
    try
        # Gradient initialization is performed locally on this process.
        # Use invokelatest because compile() (called during base_model deserialization)
        # defines new methods that aren't visible in the current world age.
        return Base.invokelatest(JuliaBUGS.Model.BUGSModelWithGradient, base_model, state.adtype)
    catch err
        @warn "Failed to reconstruct BUGSModelWithGradient" exception=(err, catch_backtrace())
        rethrow(err)
    end
end

# Deserialize BUGSModel and regenerate node functions.
function Serialization.deserialize(s::Serialization.AbstractSerializer, ::Type{<:BUGSModel})
    state = Serialization.deserialize(s)

    # Reconstruct the model; compile regenerates process-local node functions.
    model = compile(state.model_def, state.data, state.evaluation_env)
    model = settrans(model, state.transformed)

    # Restore the original evaluation mode.
    try
        model = JuliaBUGS.Model.set_evaluation_mode(model, state.evaluation_mode)
    catch err
        @warn "Failed to restore evaluation mode" exception=(err, catch_backtrace())
    end

    return model
end
