using JuliaBUGS
include("../src/BUGSExamples/BUGSExamples.jl")

volume_i_examples = BUGSExamples.volume_i_examples;

const report_file = "/home/sunxd/JuliaBUGS.jl/notebooks/test_report.jl"
example_names = (
    # :blockers,
    :bones,
    :dogs,
    # :dyes,
    :epil,
    :equiv,
    :inhalers,
    :kidney,
    :leuk,
    :leukfr,
    :lsat,
    :magnesium,
    :mice,
    :oxford,
    # :pumps,
    # :rats,
    :salm,
    # :seeds,
    :stacks,
    # :surgical_simple,
    # :surgical_realistic,
)
function test_all_examples(examples, report_file, examples_to_test)
    open(report_file, "w+") do f
        for k in example_names
            v = volume_i_examples[k]
            println(f, "Testing $(k) ...")
            model_def = v.model_def
            data = v.data
            inits = v.inits[1]
            try
                p = compile(model_def, data, inits)
                initial_θ = JuliaBUGS.gen_init_params(p)
                logp = p(initial_θ)
                println(f, "logp = ", logp)
            catch e
                println(f, "Error: ", e)
            end
            println(f)
        end
    end
end

test_all_examples(volume_i_examples, report_file, example_names)
