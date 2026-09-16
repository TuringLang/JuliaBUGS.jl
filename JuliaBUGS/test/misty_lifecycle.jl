@testset "MistyClosure lifecycle in fresh processes" begin
    project = dirname(Base.active_project())
    script = joinpath(@__DIR__, "misty_lifecycle_process.jl")
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
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project $script $packages`
        @test success(pipeline(cmd; stdout=stdout, stderr=stderr))
    end
end
