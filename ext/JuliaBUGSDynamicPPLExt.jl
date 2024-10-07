module JuliaBUGSDynamicPPLExt

using DynamicPPL: DynamicPPL, OrderedDict
using JuliaBUGS: JuliaBUGS, Bijectors, VarName

"""
    get_params_varinfo(model::JuliaBUGS.BUGSModel[, evaluation_env::NamedTuple])

Returns a `DynamicPPL.SimpleVarInfo` object containing only the parameter values of the model.
If `evaluation_env` is provided, it will be used; otherwise, `model.evaluation_env` will be used.
"""
function get_params_varinfo(
    model::JuliaBUGS.BUGSModel, evaluation_env::NT = model.evaluation_env
) where {NT <: NamedTuple}
    d = OrderedDict{VarName,Any}()
    for v in model.parameters
        if !model.transformed
            d[v] = AbstractPPL.get(evaluation_env, v)
        else
            (; node_function, node_args, loop_vars) = model.g[v]
            args = prepare_arg_values(node_args, evaluation_env, loop_vars)
            dist = node_function(; args...)
            d[v] = Bijectors.transform(
                Bijectors.bijector(dist), AbstractPPL.get(evaluation_env, v)
            )
        end
    end
    logp = JuliaBUGS.evaluate!!(model, JuliaBUGS.DefaultContext())[2]
    return DynamicPPL.SimpleVarInfo(
        d,
        logp,
        if model.transformed
            DynamicPPL.DynamicTransformation()
        else
            DynamicPPL.NoTransformation()
        end,
    )
end

end # module
