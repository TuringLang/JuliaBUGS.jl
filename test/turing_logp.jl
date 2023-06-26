@model function rats(Y, x, xbar, N, T)
    var"alpha.c" ~ JuliaBUGS.dnorm(0.0, 1.0E-6)
    var"alpha.tau" ~ JuliaBUGS.dgamma(0.001, 0.001)
    var"beta.c" ~ JuliaBUGS.dnorm(0.0, 1.0E-6)
    var"beta.tau" ~ JuliaBUGS.dgamma(0.001, 0.001)
    var"tau.c" ~ JuliaBUGS.dgamma(0.001, 0.001)

    alpha = Vector{Real}(undef, N)
    beta = Vector{Real}(undef, N)
    mu = Matrix{Real}(undef, N, T)

    for i in 1:N
        alpha[i] ~ JuliaBUGS.dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ JuliaBUGS.dnorm(var"beta.c", var"beta.tau")

        for j in 1:T
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
            Y[i, j] ~ JuliaBUGS.dnorm(mu[i, j], var"tau.c")
        end
    end

    sigma = 1 / sqrt(var"tau.c")
    alpha0 = var"alpha.c" - xbar * var"beta.c"

    return alpha0, sigma
end

# use eval to unpack the data, this is unsafe, only use it for testing
function unpack_with_eval(obj::NamedTuple)
    for field in collect(keys(obj))
        eval(Expr(:(=), field, :($obj.$field)))
    end
end




function test_single_example(example_name, transform::Bool = true)
    example = getfield(JuliaBUGS.BUGSExamples.volume_i_examples, example_name)

    unpack_with_eval(example.data)

    # Turing Model
    eval(Expr(:(=), :turing_model, Expr(:call, example_name, arg_list[example_name]...)))

    # JuliaBUGS LogDensityProblems
    p = compile(example.model_def, example.data, example.inits[1])
    # during the compilation, a SimpleVarInfo is created
    vi = deepcopy(p.ℓ.re.prototype)

    turing_logp = getlogp(
        last(
            DynamicPPL.evaluate!!(
                turing_model, DynamicPPL.settrans!!(vi, false), DefaultContext()
            ),
        ),
    )

    julia_bugs_logp = getlogp(vi)

    @test turing_logp ≈ julia_bugs_logp atol = 1e-6
end

@testitem "turing_logp" begin
    for example_name in tested_bugs_examples
        test_single_example(example_name)
    end
end



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

using Bijectors
b = Bijectors.Logit(0, 10)
dist = transformed(Gamma(2, 2), b)
rand(dist)