@testset "MistyClosure calls" begin
    env = (x=2.0,)
    loop_vars = (i=1,)
    signature = Tuple{typeof(env),typeof(loop_vars)}
    f = JuliaBUGS._make_misty_closure(
        :((env, loop_vars) -> env.x + loop_vars.i), JuliaBUGS, signature
    )
    @test f(env, loop_vars) == 3.0
    @test f((x=2.0f0,), loop_vars) === 3.0f0

    constant = JuliaBUGS._make_misty_closure(
        :((env, loop_vars) -> dnorm(0, 1)), JuliaBUGS, signature
    )
    @test constant(env, loop_vars) == dnorm(0, 1)
end
