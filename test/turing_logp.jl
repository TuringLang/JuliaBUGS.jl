using JuliaBUGS: dnorm, dgamma, dbin, dcat

using JuliaBUGS: logistic, exp

include("test_models/bugs_models_in_turing.jl")
tested_bugs_examples = [:rats, :blockers, :bones, :dogs]

for example_name in tested_bugs_examples
    test_single_example(example_name)
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
