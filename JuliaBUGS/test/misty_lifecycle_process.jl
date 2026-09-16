# Invoked by misty_lifecycle.jl, with no AD backend loaded before model compilation.
using Test, JuliaBUGS, LogDensityProblems, ADTypes, Serialization
pushfirst!(LOAD_PATH, only(ARGS))
using MistyNormalA, MistyNormalB

const models = (MistyNormalA.model, MistyNormalB.model)
const generated = (MistyNormalA.generated, MistyNormalB.generated)
const x = [0.5]
expected(mean) = -log(2pi) - ((x[1] - mean)^2 + (1 - x[1]^2)^2) / 2
expected_gradient(mean) = [-(x[1] - mean) + 2x[1] * (1 - x[1]^2)]

@testset "Restored package models" begin
    for (model, gen, mean) in zip(models, generated, (0, 3))
        @test isempty(gen.log_density_computation_function.specializations)
        @test all(
            isempty(f.specializations) for
            f in model.graph_evaluation_data.node_function_vals
        )
        @test LogDensityProblems.logdensity(model, x) ≈ expected(mean)
        @test LogDensityProblems.logdensity(gen, x) ≈ expected(mean)
        @test LogDensityProblems.logdensity(model, Float32.(x)) ≈ expected(mean)
        io = IOBuffer()
        serialize(io, gen)
        seekstart(io)
        restored = deserialize(io)
        @test LogDensityProblems.logdensity(restored, x) ≈ expected(mean)
        regenerated = JuliaBUGS.Model.regenerate_log_density_function(model; force=true)
        @test regenerated.log_density_computation_function(regenerated.evaluation_env, x) ≈
            expected(mean)
    end
end

using Mooncake, DifferentiationInterface, ForwardDiff, ReverseDiff
@testset "Backends loaded after compilation and restoration" begin
    for (model, gen, mean) in zip(models, generated, (0, 3))
        for (base, ad) in (
            (model, AutoMooncake(; config=nothing)),
            (gen, AutoMooncake(; config=nothing)),
            (gen, AutoMooncakeForward(; config=nothing)),
            (model, AutoForwardDiff()),
            (model, AutoReverseDiff()),
        )
            wrapped = JuliaBUGS.BUGSModelWithGradient(base, ad)
            value, gradient = LogDensityProblems.logdensity_and_gradient(wrapped, x)
            @test value ≈ expected(mean)
            @test gradient ≈ expected_gradient(mean)
            io = IOBuffer()
            serialize(io, wrapped)
            seekstart(io)
            restored = deserialize(io)
            value, gradient = LogDensityProblems.logdensity_and_gradient(restored, x)
            @test value ≈ expected(mean)
            @test gradient ≈ expected_gradient(mean)
        end
    end
end

@testset "Restoration preserves original source bindings" begin
    for model in models
        for f in model.graph_evaluation_data.node_function_vals
            @test getproperty(parentmodule(f.source), nameof(typeof(f.source))) ===
                typeof(f.source)
        end
    end
    for gen in generated
        source = gen.log_density_computation_function.source
        @test getproperty(parentmodule(source), nameof(typeof(source))) === typeof(source)
    end
end
