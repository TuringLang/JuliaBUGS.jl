using ADTypes, Chairmarks, DifferentiationInterface, ForwardDiff, JuliaBUGS
using LogDensityProblems, Mooncake, ReverseDiff

function benchmark_generated_functions()
    model_def = @bugs begin
        μ ~ dnorm(0, 0.01)
        τ ~ dgamma(2, 2)
        for i in 1:N
            y[i] ~ dnorm(μ, τ)
        end
    end
    data = (N=10, y=collect(range(-1.0, 1.0; length=10)))
    graph = compile(model_def, data, (μ=0.0, τ=1.0))
    generated = JuliaBUGS.set_evaluation_mode(
        graph, JuliaBUGS.UseGeneratedLogDensityFunction()
    )
    for (adtype, model) in (
        (AutoForwardDiff(), graph),
        (AutoReverseDiff(), graph),
        (AutoMooncake(; config=nothing), graph),
        (AutoMooncake(; config=nothing), generated),
        (AutoMooncakeForward(; config=nothing), generated),
    )
        gradient_model = JuliaBUGS.BUGSModelWithGradient(model, adtype)
        x = JuliaBUGS.getparams(gradient_model.base_model)
        result = minimum(
            Chairmarks.@be LogDensityProblems.logdensity_and_gradient($gradient_model, $x)
        )
        println((; backend=adtype, mode=model.evaluation_mode, result.time, result.bytes))
    end
end

benchmark_generated_functions()
