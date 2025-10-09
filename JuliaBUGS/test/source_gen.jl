using BangBang
using Bijectors
using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using LogDensityProblems
using OrderedCollections

test_examples = [
    :rats,
    :pumps,
    :dogs,
    :seeds,
    :surgical_realistic,
    :magnesium,
    :salm,
    :equiv,
    :dyes,
    :stacks,
    :epil,
    :blockers,
    :oxford,
    :lsat,
    :bones,
    :mice,
    :kidney,
    :leuk,
    :leukfr,
    :dugongs,
    :air,
    :birats,
    :schools,
    :cervix,
]

@testset "source_gen: $example_name" for example_name in test_examples
    (; model_def, data, inits) = getfield(JuliaBUGS.BUGSExamples, example_name)
    model = compile(model_def, data, inits)
    params = Base.invokelatest(JuliaBUGS.getparams, model)
    result_with_bugsmodel = begin
        model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
        LogDensityProblems.logdensity(model, params)
    end
    result_with_log_density_computation_function = begin
        model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())
        LogDensityProblems.logdensity(model, params)
    end
    @test result_with_log_density_computation_function ≈ result_with_bugsmodel
end

@testset "reserved variable names are rejected" begin
    @test_throws ErrorException JuliaBUGS.__check_for_reserved_names(
        @bugs begin
            __logp__ ~ dnorm(0, 1)
        end
    )
end

@testset "mixed data transformation and deterministic assignments" begin
    model_def = @bugs begin
        for i in 1:5
            y[i] ~ Normal(0, 1)
        end
        for i in 1:5
            x[i] = y[i] + 1
        end
    end
    data = (; y=[1, 2, missing, missing, 2])

    model = compile(model_def, data)
end
