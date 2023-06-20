linear_regression = (
    model_def = @bugsast begin
        for i in 1:N
            Y[i] ~ dnorm(μ[i], τ)
            μ[i] = α + β * (x[i] - xbar)
        end
        τ ~ dgamma(0.001, 0.001)
        σ = 1 / sqrt(τ)
        logτ = log(τ)
        α ~ dnorm(0.0, 1e-6)
        β ~ dnorm(0.0, 1e-6)
    end,
    data = Dict(:x => [1, 2, 3, 4, 5], :Y => [1, 3, 3, 3, 5], :xbar => 3, :N => 5), 
    inits = [NamedTuple(), NamedTuple()]
)

using Turing, Test
test_model_def_1 = @bugsast begin
    a ~ dgamma(2, 2)
end
test_model_1_bugs = compile(test_model_def_1, Dict(), Dict(:a=>2))
@model function test_model_1_dppl_func()
    a ~ dgamma(2, 2)
end
test_model_1_dppl = test_model_1_dppl_func()
vi = SimpleVarInfo(Dict((@varname(a) => 2)))

# DynamicTransformation
vi = DynamicPPL.settrans!!(vi, true)
test_model_1_bugs = @set test_model_1_bugs.varinfo = vi
evaluate!!(test_model_1_bugs, JuliaBUGS.DefaultContext()).logp
last(evaluate!!(test_model_1_dppl, DynamicPPL.settrans!!(vi, true), DynamicPPL.DefaultContext())).logp
# NoTransformation
vi = DynamicPPL.settrans!!(vi, false)
test_model_1_bugs = @set test_model_1_bugs.varinfo = vi
evaluate!!(test_model_1_bugs, JuliaBUGS.DefaultContext()).logp
last(evaluate!!(test_model_1_dppl, vi, DynamicPPL.DefaultContext())).logp
