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

    # Test with graph evaluation
    result_with_bugsmodel = begin
        model_graph = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
        params_graph = Base.invokelatest(JuliaBUGS.getparams, model_graph)
        Base.invokelatest(LogDensityProblems.logdensity, model_graph, params_graph)
    end

    # Test with generated function (triggers on-demand generation)
    result_with_log_density_computation_function = begin
        model_gen = JuliaBUGS.set_evaluation_mode(
            model, JuliaBUGS.UseGeneratedLogDensityFunction()
        )
        # Explicitly check that source generation succeeded
        @test !isnothing(model_gen.log_density_computation_function)
        # Extract params after setting mode to account for potential parameter reordering
        params_gen = Base.invokelatest(JuliaBUGS.getparams, model_gen)
        Base.invokelatest(LogDensityProblems.logdensity, model_gen, params_gen)
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

@testset "state-space models (SSM) transformation" begin
    # Helper: check if source generation succeeds, returns (success::Bool, diagnostics)
    function can_generate_source(model_def, data)
        eval_env = JuliaBUGS.semantic_analysis(model_def, data)
        g = JuliaBUGS.create_graph(model_def, eval_env)
        diags = String[]
        lowered, reconstructed = JuliaBUGS._generate_lowered_model_def(
            model_def, g, eval_env; diagnostics=diags
        )
        return lowered !== nothing, diags
    end

    # Helper: verify generated code produces same log density as graph evaluation
    function generated_matches_graph(model_def, data)
        model = compile(model_def, data)
        result_graph = begin
            m = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
            params = Base.invokelatest(JuliaBUGS.getparams, m)
            Base.invokelatest(LogDensityProblems.logdensity, m, params)
        end
        result_gen = begin
            m = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())
            params = Base.invokelatest(JuliaBUGS.getparams, m)
            Base.invokelatest(LogDensityProblems.logdensity, m, params)
        end
        return result_graph ≈ result_gen
    end

    @testset "basic SSM with self-recursion" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(x[t - 1], sigma_x)
            end
            for t in 1:T
                y[t] ~ Normal(x[t], sigma_y)
            end
        end
        data = (T=10, sigma_x=0.5, sigma_y=0.3)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "lagged observations" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(x[t - 1], sigma_x)
            end
            y[1] ~ Normal(x[1], sigma_y)
            for t in 2:T
                y[t] ~ Normal(x[t - 1], sigma_y)
            end
        end
        data = (T=10, sigma_x=0.5, sigma_y=0.3)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "cross-coupled SSM (mutual lag-1)" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            y[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(y[t - 1], sigma_x)
                y[t] ~ Normal(x[t - 1], sigma_y)
            end
        end
        data = (T=10, sigma_x=0.5, sigma_y=0.3)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "negative dependence (read future) rejected" begin
        model_def = @bugs begin
            for t in 1:(T - 1)
                x[t] ~ Normal(x[t + 1], sigma)
            end
            x[T] ~ Normal(0, 1)
        end
        @test !first(can_generate_source(model_def, (T=10, sigma=0.7)))
    end

    @testset "grid SSM (multi-dimensional)" begin
        model_def = @bugs begin
            for i in 1:I
                x[i, 1] ~ Normal(0, 1)
                for t in 2:T
                    x[i, t] ~ Normal(x[i, t - 1], sigma)
                end
            end
            for i in 1:I
                for t in 1:T
                    y[i, t] ~ Normal(x[i, t], sigma_y)
                end
            end
        end
        data = (I=3, T=10, sigma=0.7, sigma_y=0.3)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "inter-loop cycle rejected" begin
        # Even/odd split loops with mutual dependencies cannot be fused automatically
        model_def = @bugs begin
            sumX[1] = x[1]
            for i in 2:N
                sumX[i] = sumX[i - 1] + x[i]
            end
            for k in 1:K
                x[2 * k] ~ Normal(sumX[2 * k - 1], tau)
            end
            for k in 1:Km1
                x[2 * k + 1] ~ Gamma(sumX[2 * k], tau)
            end
        end
        data = (N=10, K=5, Km1=4, tau=1.2, x=Union{Float64,Missing}[1.0; fill(missing, 9)])
        @test !first(can_generate_source(model_def, data))
    end

    @testset "deterministic cycle rejected" begin
        # Cyclic deterministic dependencies cannot be resolved
        model_def = @bugs begin
            z[1] = 0.0
            z[2] = x[1] + 0.0
            y[1] = 0.0
            y[2] = x[3] + 0.0
            for i in 1:3
                x[i] = y[a[i]] + z[b[i]]
            end
        end
        @test !first(can_generate_source(model_def, (a=[2, 2, 1], b=[2, 1, 2])))
    end

    @testset "multi-statement loop with mixed dependencies" begin
        # Self-recursion (positive) + same-iteration dependency (zero)
        # Should stay as single fused loop with correct intra-iteration order
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            y[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(x[t - 1], sigma)  # positive self-dep
                y[t] ~ Normal(x[t], sigma)       # zero dep (same iteration)
            end
        end
        data = (T=10, sigma=0.5)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "three-way cross-coupled SSM" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            y[1] ~ Normal(0, 1)
            z[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(y[t - 1] + z[t - 1], sigma)
                y[t] ~ Normal(x[t - 1] + z[t - 1], sigma)
                z[t] ~ Normal(x[t - 1] + y[t - 1], sigma)
            end
        end
        data = (T=10, sigma=0.5)
        @test first(can_generate_source(model_def, data))
        @test generated_matches_graph(model_def, data)
    end

    @testset "@bugs_primitive works with UseGeneratedLogDensityFunction" begin
        my_square(x) = x^2
        JuliaBUGS.@bugs_primitive my_square

        model_def = @bugs begin
            x ~ dnorm(0, 1)
            y = my_square(x)
            z ~ dnorm(y, 1)
        end

        model = compile(model_def, (z=1.0,))
        model_graph = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGraph())
        model_gen = JuliaBUGS.set_evaluation_mode(
            model, JuliaBUGS.UseGeneratedLogDensityFunction()
        )

        params = Base.invokelatest(JuliaBUGS.getparams, model_graph)
        ld_graph = Base.invokelatest(LogDensityProblems.logdensity, model_graph, params)
        ld_gen = Base.invokelatest(LogDensityProblems.logdensity, model_gen, params)

        @test isapprox(ld_graph, ld_gen; rtol=1e-10)
    end
end
