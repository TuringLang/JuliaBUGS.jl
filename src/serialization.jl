using Serialization

function Serialization.serialize(s::Serialization.AbstractSerializer, model::BUGSModel)
    if !isnothing(model.base_model)
        throw(ArgumentError("Conditioned model can't be serialized."))
    end
    Serialization.writetag(s.io, Serialization.OBJECT_TAG)
    Serialization.serialize(s, typeof(model))
    Serialization.serialize(s, model.transformed)
    Serialization.serialize(s, model.model_def)
    Serialization.serialize(s, model.data)
    Serialization.serialize(s, model.evaluation_env)
    return nothing
end

function Serialization.deserialize(s::Serialization.AbstractSerializer, ::Type{<:BUGSModel})
    transformed = Serialization.deserialize(s)
    model_def = Serialization.deserialize(s)
    data = Serialization.deserialize(s)
    evaluation_env = Serialization.deserialize(s)
    # use evaluation_env as initialization to restore the values
    model = compile(model_def, data, evaluation_env)
    return settrans(model, transformed)
end
