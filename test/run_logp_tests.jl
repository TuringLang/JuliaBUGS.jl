function load_dictionary(example_name, data_or_init, replace_period=true)
    example = JuliaBUGS.BUGSExamples.VOLUME_I[example_name]
    if data_or_init == :data
        _d = example.data
    elseif data_or_init == :init
        _d = example.inits[1]
    else
        error("data_or_init must be either :data or :init")
    end
    d = Dict{Symbol,Any}()
    for _k in keys(_d)
        if replace_period
            k = Symbol(replace(String(_k), "." => "_"))
        end
        d[k] = _d[_k]
    end
    return d
end

function params_in_dppl_model(dppl_model)
    return keys(
        DynamicPPL.evaluate!!(
            dppl_model, SimpleVarInfo(Dict{VarName,Any}()), DynamicPPL.SamplingContext()
        )[2],
    )
end
