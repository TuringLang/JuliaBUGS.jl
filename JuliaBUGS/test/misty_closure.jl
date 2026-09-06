@testset "MistyClosure calls" begin
    env = (x=2.0,)
    loop_vars = (i=1,)
    f = JuliaBUGS._make_misty_closure(:((env, loop_vars) -> env.x + loop_vars.i), JuliaBUGS)
    @test f(env, loop_vars) == 3.0
    @test f((x=2.0f0,), loop_vars) === 3.0f0

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
end

@testset "Specializations retain the source world" begin
    expr = :((env, loop_vars) -> transform_value(env.x))
    f = JuliaBUGS._make_misty_closure(expr, MistyClosureTestContext)
    @test f((x=2.0,), (;)) == 4.0

    Core.eval(MistyClosureTestContext, :(transform_value(x) = 3x))
    @test f((x=2,), (;)) == 4
    @test @inferred(f((x=2.0f0,), (;))) === 4.0f0
    updated = JuliaBUGS._make_misty_closure(expr, MistyClosureTestContext)
    @test updated((x=2.0,), (;)) == 6.0

    for adtype in (
        AutoForwardDiff(),
        AutoReverseDiff(),
        AutoMooncake(; config=nothing),
        AutoMooncakeForward(; config=nothing),
    )
        target = x -> f((x=x[1],), (;))
        prep = AbstractPPL.prepare(adtype, target, [2.0])
        value, gradient = AbstractPPL.value_and_gradient!!(prep, [2.0])
        @test value == 4.0
        @test gradient == [4.0]
    end
end

@testset "Nested Mooncake rules" begin
    f = JuliaBUGS._make_misty_closure(:((env, vars) -> env.x * env.x), JuliaBUGS)
    target = x -> f((x=x[1],), (;))
    for adtype in (AutoMooncake(; config=nothing), AutoMooncakeForward(; config=nothing))
        prep = AbstractPPL.prepare(adtype, target, [2.0])
        copied_prep = AbstractPPL.prepare(adtype, target, [3.0])
        for (cache, x) in ((prep, [2.0]), (copied_prep, [3.0]), (prep, [4.0]))
            value, gradient = AbstractPPL.value_and_gradient!!(cache, x)
            @test value == x[1]^2
            @test gradient == [2x[1]]
        end
    end
end
