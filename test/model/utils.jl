using Test
using JuliaBUGS
using JuliaBUGS.Model: get_mutable_symbols, smart_copy_evaluation_env, condition
using JuliaBUGS: @bugs, compile, @varname

@testset "Model Utilities" begin
    @testset "get_mutable_symbols" begin
        # Test model with parameters and deterministic nodes
        model_def = @bugs begin
            # Parameters (mutable)
            mu ~ Normal(0, 1)
            sigma ~ Gamma(1, 1)

            # Deterministic nodes (mutable)
            precision = 1 / sigma^2
            scaled_mu = mu * 2

            # Observations (immutable)
            for i in 1:N
                y[i] ~ Normal(mu, sigma)
            end
        end

        N = 10
        y_data = randn(N)
        model = compile(model_def, (; N=N, y=y_data))

        mutable_syms = get_mutable_symbols(model)

        # Check that parameters are included
        @test :mu in mutable_syms
        @test :sigma in mutable_syms

        # Check that deterministic nodes are included
        @test :precision in mutable_syms
        @test :scaled_mu in mutable_syms

        # Check that data is NOT included
        @test !(:y in mutable_syms)
        @test !(:N in mutable_syms)

        # Test with array parameters
        model_def2 = @bugs begin
            for j in 1:3
                theta[j] ~ Beta(1, 1)
            end
            sum_theta = sum(theta[1:3])
            for i in 1:N
                x[i] ~ Bernoulli(sum_theta / 3)
            end
        end

        x_data = [0, 1, 1, 0, 1]
        model2 = compile(model_def2, (; N=5, x=x_data))
        mutable_syms2 = get_mutable_symbols(model2)

        @test :theta in mutable_syms2
        @test :sum_theta in mutable_syms2
        @test !(:x in mutable_syms2)
    end

    @testset "smart_copy_evaluation_env" begin
        # Create a test environment with various types
        env = (
            # Mutable parameters
            a=[1.0, 2.0, 3.0],
            b=5.0,

            # Immutable data
            large_data=randn(1000, 1000),
            small_data=[1, 2, 3],
            constant=42,
        )

        mutable_syms = Set([:a, :b])

        # Perform smart copy
        new_env = smart_copy_evaluation_env(env, mutable_syms)

        # Test that mutable fields are copied (different objects)
        @test new_env.a !== env.a
        @test new_env.a == env.a
        @test new_env.b == env.b

        # Test that immutable fields are shared (same objects)
        @test new_env.large_data === env.large_data
        @test new_env.small_data === env.small_data
        @test new_env.constant === env.constant

        # Modify the copy and ensure original is unchanged
        new_env.a[1] = 999.0
        @test env.a[1] == 1.0
        @test new_env.a[1] == 999.0

        # But modifying shared data affects both
        new_env.large_data[1, 1] = 777.0
        @test env.large_data[1, 1] == 777.0
    end

    @testset "Integration with BUGSModel" begin
        # Test that smart copying is used in evaluation
        model_def = @bugs begin
            theta ~ Beta(1, 1)
            p = theta * 2
            for i in 1:N
                y[i] ~ Bernoulli(theta)
            end
        end

        N = 100
        y_data = rand(0:1, N)
        model = compile(model_def, (; N=N, y=y_data))

        # Check that mutable_symbols was computed
        @test :theta in model.mutable_symbols
        @test :p in model.mutable_symbols
        @test !(:y in model.mutable_symbols)
        @test !(:N in model.mutable_symbols)

        # Test that evaluation uses smart copy (indirectly)
        # by checking memory efficiency
        original_env = model.evaluation_env

        # Call evaluate_with_rng!! which should use smart_copy_evaluation_env
        using Random
        rng = Random.MersenneTwister(123)
        new_env, _ = JuliaBUGS.Model.evaluate_with_rng!!(rng, model)

        # The data arrays should be the same objects (not copied)
        @test new_env.y === original_env.y
        @test new_env.N === original_env.N

        # But parameters should be different objects
        @test new_env.theta !== original_env.theta
    end

    @testset "Performance comparison" begin
        # Create a model with large data
        N = 10000
        K = 50

        model_def = @bugs begin
            # Small number of parameters
            mu ~ Normal(0, 1)
            sigma ~ Gamma(1, 1)

            # Large data
            for i in 1:N
                y[i] ~ Normal(mu, sigma)
            end
        end

        y_data = randn(N)
        model = compile(model_def, (; N=N, y=y_data))

        # Time smart copy vs deepcopy
        env = model.evaluation_env
        mutable_syms = model.mutable_symbols

        # Warm up
        smart_copy_evaluation_env(env, mutable_syms)
        deepcopy(env)

        # Measure smart copy
        smart_time = @elapsed for _ in 1:100
            smart_copy_evaluation_env(env, mutable_syms)
        end

        # Measure deepcopy
        deep_time = @elapsed for _ in 1:100
            deepcopy(env)
        end

        # Smart copy should be faster for models with large data
        @test smart_time < deep_time

        # Print performance improvement
        @info "Performance: smart_copy is $(round(deep_time/smart_time, digits=2))x faster than deepcopy"
    end

    @testset "Mutable symbols update with conditioning" begin
        # Create a model with multiple parameters
        model_def = @bugs begin
            a ~ Normal(0, 1)
            b ~ Normal(a, 1)
            c = a + b
            d ~ Normal(c, 1)
            for i in 1:N
                y[i] ~ Normal(d, 1)
            end
        end

        N = 5
        y_data = randn(N)
        model = compile(model_def, (; N=N, y=y_data))

        # Check initial mutable symbols
        @test :a in model.mutable_symbols
        @test :b in model.mutable_symbols
        @test :c in model.mutable_symbols  # deterministic
        @test :d in model.mutable_symbols
        @test !(:y in model.mutable_symbols)
        @test !(:N in model.mutable_symbols)

        # Condition on 'a' - it should no longer be mutable
        model_cond_a = condition(model, (; a=1.0))
        @test !(:a in model_cond_a.mutable_symbols)  # 'a' is now observed
        @test :b in model_cond_a.mutable_symbols
        @test :c in model_cond_a.mutable_symbols
        @test :d in model_cond_a.mutable_symbols

        # Condition on 'b' as well
        model_cond_ab = condition(model_cond_a, (; b=2.0))
        @test !(:a in model_cond_ab.mutable_symbols)
        @test !(:b in model_cond_ab.mutable_symbols)
        @test :c in model_cond_ab.mutable_symbols  # still mutable (deterministic)
        @test :d in model_cond_ab.mutable_symbols

        # Condition on all parameters
        model_cond_all = condition(model_cond_ab, (; d=3.0))
        @test !(:a in model_cond_all.mutable_symbols)
        @test !(:b in model_cond_all.mutable_symbols)
        @test :c in model_cond_all.mutable_symbols  # deterministic nodes stay mutable
        @test !(:d in model_cond_all.mutable_symbols)
    end
end
