using JuliaBUGS: 
    dnorm,
    dgamma,
    dbin,
    dcat

using JuliaBUGS: 
    logistic,
    exp

include("test_models/bugs_models.jl")
tested_bugs_examples = [:rats, :blockers, :bones, :dogs]

for example_name in tested_bugs_examples
    test_single_example(example_name)
end

# use eval to unpack the data, this is unsafe, only use it for testing
function unpack_with_eval(obj::NamedTuple)
    return unpack_with_eval(obj, collect(keys(obj)))
end
function unpack_with_eval(obj, fields)
    for field in fields
        eval(Expr(:(=), field, :($obj.$field))) # !unsafe
    end
end

function test_single_example(example_name)
    example = getfield(JuliaBUGS.BUGSExamples.volume_i_examples, example_name)

    unpack_with_eval(example.data)

    # Turing Model
    eval(Expr(:(=), :turing_model, Expr(:call, example_name, arg_list[example_name]...)))

    # JuliaBUGS LogDensityProblems
    p = compile(example.model_def, example.data, example.inits[1]);
    # during the compilation, a SimpleVarInfo is created
    vi = deepcopy(p.ℓ.re.prototype)

    @test (getlogp(last(DynamicPPL.evaluate!!(turing_model, DynamicPPL.settrans!!(vi, false), DefaultContext()))) ≈ getlogp(vi))
end
