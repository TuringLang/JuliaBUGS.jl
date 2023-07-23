function compare_dppl_bugs_logps(dppl_model, bugs_model, if_transform=false)
    turing_logp = getlogp(
        last(
            DynamicPPL.evaluate!!(
                dppl_model,
                DynamicPPL.settrans!!(bugs_model.varinfo, if_transform),
                DynamicPPL.DefaultContext(),
            ),
        ),
    )
    bugs_logp = getlogp(
        evaluate!!(
            DynamicPPL.settrans!!(bugs_model, if_transform), JuliaBUGS.DefaultContext()
        ),
    )
    @debug turing_logp bugs_logp
    @test turing_logp ≈ bugs_logp atol = 1e-6
end

function load_dictionary(example_name, data_or_init, replace_period=true)
    example = JuliaBUGS.BUGSExamples.VOLUME_I[example_name]
    if data_or_init == :data
        _d = example.data
    elseif data_or_init == :init
        _d = example.inits[1]
    else
        error("data_or_init must be either :data or :init")
    end
    d = Dict{Symbol, Any}()
    for _k in keys(_d)
        if replace_period
            k = Symbol(replace(String(_k), "." => "_"))
        end
        d[k] = _d[_k]
    end
    return d
end

import DynamicPPL: tilde_assume
function DynamicPPL.tilde_assume(::DynamicPPL.IsLeaf, context::DynamicPPL.DefaultContext, right, vn, vi)
    r = vi[vn, right]
    # return vi[vn], Bijectors.logpdf_with_trans(right, r, istrans(vi, vn)), vi
    return r, Bijectors.logpdf_with_trans(right, r, istrans(vi, vn)), vi
end

function get_vi_logp(model::DynamicPPL.Model, varinfo, if_transform)
    ret_val, vi = DynamicPPL.evaluate!!(
        model, DynamicPPL.settrans!!(varinfo, if_transform), DynamicPPL.DefaultContext()
    )
    return vi, getlogp(vi)
end

function get_vi_logp(model::JuliaBUGS.BUGSModel, if_transform)
    vi = JuliaBUGS.evaluate!!(
        DynamicPPL.settrans!!(model, if_transform)
    )
    return settrans!!(JuliaBUGS.get_params_varinfo((@set model.varinfo = vi)), if_transform), getlogp(vi)
end

include("logp_dynamicppl/binomial.jl")
include("logp_dynamicppl/gamma.jl")

include("logp_dynamicppl/blockers.jl")
include("logp_dynamicppl/bones.jl")
# include("logp_dynamicppl/dogs.jl") # dogs is a strange example, come back to this later
include("logp_dynamicppl/rats.jl")

# why DynamicPPL is not a good target to test BUGS models
# currently, I produce a varinfo with the BUGS model
# I initially thought, by using this varinfo with `evaluate!!` with DefaultContext 

# TODO: write a `Context` that only use values from VarInfo and disregard other things 

# the issue is, it does use the value from VarInfo, but it bind the variable to a transformed value because it hits the 
# `isassumption` clause