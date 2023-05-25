using JuliaBUGS
using JuliaBUGS: compile

include("/home/sunxd/JuliaBUGS.jl/src/BUGSExamples/BUGSExamples.jl")

volume_i_examples = BUGSExamples.volume_i_examples;
values(examples)[1]
output_file = "./test/compile_output.txt"

# open the file for writing or create
## run all examples
report_file = "/home/sunxd/JuliaBUGS.jl/test/compile_report.txt"
example_names = (
    :blockers,
    :bones,
    :dogs,
    :dyes,
    :epil,
    :equiv,
    # :inhalers,
    :kidney,
    :leuk,
    :leukfr,
    :lsat,
    :magnesium,
    :mice,
    :oxford,
    :pumps,
    :rats,
    :salm,
    :seeds,
    :stacks,
    :surgical_simple,
    :surgical_realistic,
)
function test_all_examples(examples, report_file, examples_to_test)
    open(report_file, "w+") do f
        for k in examples_to_test
            v = examples[k]
            println(f, "Testing $(k) ...")
            model_def = v.model_def
            data = v.data
            inits = v.inits[1]
            try
                p = compile(model_def, data, inits)
                D = LogDensityProblems.dimension(p)
                logp = LogDensityProblems.logdensity(p, rand(D))
                println(f, "logp = ", logp)
            catch e
                println(f, "Error: ", e)
            end
            println(f)
        end
    end
end

test_all_examples(volume_i_examples, report_file, example_names)

for k in keys(examples)
    v = examples[k]
    println("Testing $k")
    model_def = v.model_def
    data = v.data
    inits = v.inits[1]
    try
        p = compile(model_def, data, inits)
    catch e
        println(e)
    end
end

