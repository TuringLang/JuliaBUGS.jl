using Bijectors, DynamicPPL

dist = LKJ(10, 0.5)
test_θ_transformed = rand(45)
test_θ = DynamicPPL.invlink_and_reconstruct(dist, test_θ_transformed)

value = test_θ
value_transformed, logabsdetjac = with_logabsdet_jacobian(bijector(dist), value)
logpdf(dist, value) + logabsdetjac

test_lkj = @bugs begin
    x[1:10, 1:10] ~ LKJ(10, 0.5)
end

test_lkj_model = compile(test_lkj, Dict(), Dict(:x=>test_θ))

# test param length given trans-dim bijectors
@test JuliaBUGS.get_param_length(test_lkj_model) == 100
@test JuliaBUGS.get_param_length(JuliaBUGS.settrans!!(test_lkj_model, true)) == 45

@model function lkj_test()
    x = Matrix{Float64}(undef, 10, 10)
    x ~ LKJ(10, 0.5)
end

@macroexpand @model function lkj_test()
    x = Matrix{Float64}(undef, 10, 10)
    x ~ LKJ(10, 0.5)
end

using AbstractPPL
function lkj_test(__model__::Model, __varinfo__::AbstractVarInfo, __context__::AbstractPPL.AbstractContext; )
    #= /home/sunxd/JuliaBUGS.jl/test/logp_tests/lkj.jl:26 =#
    begin
        #= /home/sunxd/JuliaBUGS.jl/test/logp_tests/lkj.jl:26 =#
        #= /home/sunxd/JuliaBUGS.jl/test/logp_tests/lkj.jl:27 =#
        x = Matrix{Float64}(undef, 10, 10)
        #= /home/sunxd/JuliaBUGS.jl/test/logp_tests/lkj.jl:28 =#
        begin
            #= /home/sunxd/.julia/packages/DynamicPPL/slbWl/src/compiler.jl:555 =#
            var"##retval#313" = begin
                    var"##dist#311" = LKJ(10, 0.5)
                    var"##vn#308" = (DynamicPPL.resolve_varnames)((VarName){:x}(), var"##dist#311")
                    var"##isassumption#309" = begin
                            if (DynamicPPL.contextual_isassumption)(__context__, var"##vn#308")
                                if !((DynamicPPL.inargnames)(var"##vn#308", __model__)) || (DynamicPPL.inmissings)(var"##vn#308", __model__)
                                    true
                                else
                                    x === missing
                                end
                            else
                                false
                            end
                        end
                    if (DynamicPPL.contextual_isfixed)(__context__, var"##vn#308")
                        x = (DynamicPPL.getfixed_nested)(__context__, var"##vn#308")
                    elseif var"##isassumption#309"
                        begin
                            (var"##value#312", __varinfo__) = (DynamicPPL.tilde_assume!!)(__context__, (DynamicPPL.unwrap_right_vn)((DynamicPPL.check_tilde_rhs)(var"##dist#311"), var"##vn#308")..., __varinfo__)
                            x = var"##value#312"
                            var"##value#312"
                        end
                    else
                        if !((DynamicPPL.inargnames)(var"##vn#308", __model__))
                            x = (DynamicPPL.getconditioned_nested)(__context__, var"##vn#308")
                        end
                        (var"##value#310", __varinfo__) = (DynamicPPL.tilde_observe!!)(__context__, (DynamicPPL.check_tilde_rhs)(var"##dist#311"), x, var"##vn#308", __varinfo__)
                        var"##value#310"
                    end
                end
            #= /home/sunxd/.julia/packages/DynamicPPL/slbWl/src/compiler.jl:556 =#
            return (var"##retval#313", __varinfo__)
        end
    end
end

function lkj_test(; )
    #= /home/sunxd/JuliaBUGS.jl/test/logp_tests/lkj.jl:26 =#
    return (Model)(lkj_test, NamedTuple{()}(()); )
end


dppl_model = lkj_test()

vi, bugs_logp = get_vi_logp(test_lkj_model, false)

vi = JuliaBUGS.get_params_varinfo(test_lkj_model, vi)

_, dppl_logp = get_vi_logp(dppl_model, vi, false)
@test bugs_logp ≈ dppl_logp rtol = 1E-6

vi, bugs_logp = get_vi_logp(test_lkj_model, true)
vi, dppl_logp = get_vi_logp(dppl_model, vi, true)
@test bugs_logp ≈ dppl_logp rtol = 1E-6

using LogDensityProblems
p = DynamicPPL.LogDensityFunction(dppl_model)

LogDensityProblems.logdensity(p, vcat(test_θ...))

t_p = DynamicPPL.LogDensityFunction(dppl_model, DynamicPPL.link!!(SimpleVarInfo(dppl_model), dppl_model), DynamicPPL.DefaultContext())
LogDensityProblems.logdensity(t_p, test_θ_transformed)
# TODO: link function need to be tested too with bijectors

JuliaBUGS.evaluate!!(test_lkj_model, LogDensityContext(), vcat(test_θ...))
JuliaBUGS.evaluate!!(JuliaBUGS.settrans!!(test_lkj_model, true), LogDensityContext(), test_θ_transformed)

using Bijectors, Distributions

invlink(Normal(), 0.5)

invlink(LKJ(10, 0.5), test_θ)

evaluate!!(t_p.model, vi_new, f.context)

svi = DynamicPPL.settrans!!(SimpleVarInfo(Dict(@varname(x) => test_θ_transformed)), true)

@enter DynamicPPL.evaluate!!(dppl_model, svi, DynamicPPL.DefaultContext())

DynamicPPL.evaluate!!(dppl_model, SimpleVarInfo(Dict(@varname(x) => test_θ)), DynamicPPL.DefaultContext())

logpdf(dist, test_θ)

with_logabsdet_jacobian(bijector(dist), test_θ)