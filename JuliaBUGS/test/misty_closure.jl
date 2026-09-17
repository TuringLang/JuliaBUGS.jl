using Test, JuliaBUGS, LogDensityProblems, ADTypes, Serialization

# A fresh process loads package models before any AD backend.
if length(ARGS) == 2 && ARGS[1] == "--misty-lifecycle"
    pushfirst!(LOAD_PATH, ARGS[2])
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
            @test regenerated.log_density_computation_function(
                regenerated.evaluation_env, x
            ) ≈ expected(mean)
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
            @test getproperty(parentmodule(source), nameof(typeof(source))) ===
                typeof(source)
        end
    end
    exit()
end

@testset "MistyClosure calls" begin
    env = (x=2.0,)
    loop_vars = (i=1,)
    f = JuliaBUGS._make_misty_closure(:((env, loop_vars) -> env.x + loop_vars.i), JuliaBUGS)
    @test f(env, loop_vars) == 3.0
    @test f((x=2.0f0,), loop_vars) === 3.0f0
    @test JuliaBUGS._make_misty_closure(:((env, vars) -> typeof(env.x)), JuliaBUGS)(
        env, loop_vars
    ) === Float64

    constant = JuliaBUGS._make_misty_closure(:((env, loop_vars) -> dnorm(0, 1)), JuliaBUGS)
    @test constant(env, loop_vars) == dnorm(0, 1)
end

@testset "Constant results preserve effects" begin
    env = (calls=Ref(0),)
    f = JuliaBUGS._make_misty_closure(
        :((env, loop_vars) -> begin
            env.calls[] += 1
            dnorm(0, 1)
        end), JuliaBUGS
    )
    @test f(env, (;)) == dnorm(0, 1)
    @test env.calls[] == 1
end

module MistyClosureTestContext
transform_value(x) = x * x
dnorm(args...) = :caller_namespace
end

@testset "Source ownership and specialization" begin
    expr = :((env, loop_vars) -> transform_value(env.x))
    f = JuliaBUGS._make_misty_closure(expr, MistyClosureTestContext)
    other = JuliaBUGS._make_misty_closure(
        :((env, loop_vars) -> 3env.x), MistyClosureTestContext
    )
    @test f((x=2.0,), (;)) == 4.0
    @test other((x=2.0,), (;)) == 6.0
    @test f((x=2,), (;)) == 4
    @test @inferred(f((x=2.0f0,), (;))) === 4.0f0
end

@testset "Concurrent specializations" begin
    f = JuliaBUGS._make_misty_closure(:((env, vars) -> env.x^2), JuliaBUGS)
    tasks = [Threads.@spawn(f((x=x,), (;))) for x in (2.0, 3.0f0, 4, 5.0)]
    @test fetch.(tasks) == [4.0, 9.0f0, 16, 25.0]
    @test f((x=3.0f0,), (;)) === 9.0f0
end

@testset "Generated source keeps JuliaBUGS namespace" begin
    expr = :((env, vars) -> dnorm(env.x, 1))
    f = JuliaBUGS._make_misty_closure(expr, JuliaBUGS, MistyClosureTestContext)
    @test f((x=2.0,), (;)) == dnorm(2, 1)
end

@testset "MistyClosure lifecycle in fresh processes" begin
    project = dirname(Base.active_project())
    script = @__FILE__
    mktempdir() do packages
        for (name, mean) in (("MistyNormalA", 0), ("MistyNormalB", 3))
            src = joinpath(packages, name, "src")
            mkpath(src)
            write(
                joinpath(src, "$name.jl"),
                """
module $name
using JuliaBUGS, JuliaBUGS.BUGSPrimitives, LogDensityProblems, ADTypes
const model = compile(@bugs(begin
    x ~ dnorm($mean, 1)
    y ~ dnorm(x * x, 1)
end), (; y=1.0), (; x=0.5); eval_module=@__MODULE__)
const generated = JuliaBUGS.set_evaluation_mode(
    model, JuliaBUGS.UseGeneratedLogDensityFunction())
const density = LogDensityProblems.logdensity(generated, [0.5])
const ad_error = try
    JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake())
catch err
    err
end
@assert ad_error isa ArgumentError
@assert occursin("after package loading", sprint(showerror, ad_error))
end
""",
            )
            # Separate compilation processes used to produce colliding gensym IDs.
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project -e $("pushfirst!(LOAD_PATH, " * repr(packages) * "); using " * name)`
            @test success(pipeline(cmd; stdout=stdout, stderr=stderr))
        end
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project $script --misty-lifecycle $packages`
        @test success(pipeline(cmd; stdout=stdout, stderr=stderr))
    end
end
