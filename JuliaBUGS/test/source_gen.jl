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
        Base.invokelatest(LogDensityProblems.logdensity, model, params)
    end
    result_with_log_density_computation_function = begin
        model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())
        Base.invokelatest(LogDensityProblems.logdensity, model, params)
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
    # Helper: run semantic analysis + graph + source-generation and return success flag + diags
    function _gen_ok(model_def, data)
        eval_env = JuliaBUGS.semantic_analysis(model_def, data)
        g = JuliaBUGS.create_graph(model_def, eval_env)
        diags = String[]
        lowered, reconstructed = JuliaBUGS._generate_lowered_model_def(
            model_def, g, eval_env; diagnostics=diags
        )
        return lowered !== nothing, diags
    end

    # 1) Basic SSM with self-recursion and observations
    model_def1 = @bugs begin
        x[1] ~ Normal(0, 1)
        for t in 2:T
            x[t] ~ Normal(x[t - 1], sigma_x)
        end
        for t in 1:T
            y[t] ~ Normal(x[t], sigma_y)
        end
    end
    ok1, _ = _gen_ok(model_def1, (T=10, sigma_x=0.5, sigma_y=0.3))
    @test ok1

    # 2) Lagged observations depend on previous state
    model_def2 = @bugs begin
        x[1] ~ Normal(0, 1)
        for t in 2:T
            x[t] ~ Normal(x[t - 1], sigma_x)
        end
        y[1] ~ Normal(x[1], sigma_y)
        for t in 2:T
            y[t] ~ Normal(x[t - 1], sigma_y)
        end
    end
    ok2, _ = _gen_ok(model_def2, (T=10, sigma_x=0.5, sigma_y=0.3))
    @test ok2

    # 3) Cross-coupled SSM (mutual lag-1) in a single time loop
    model_def3 = @bugs begin
        x[1] ~ Normal(0, 1)
        y[1] ~ Normal(0, 1)
        for t in 2:T
            x[t] ~ Normal(y[t - 1], sigma_x)
            y[t] ~ Normal(x[t - 1], sigma_y)
        end
    end
    ok3, _ = _gen_ok(model_def3, (T=10, sigma_x=0.5, sigma_y=0.3))
    @test ok3

    # 4) Invalid negative dependence (read future state)
    model_def4 = @bugs begin
        for t in 1:(T - 1)
            x[t] ~ Normal(x[t + 1], sigma)
        end
        x[T] ~ Normal(0, 1)
    end
    ok4, _ = _gen_ok(model_def4, (T=10, sigma=0.7))
    @test !ok4

    # 5) Grid SSM: independent per-row recurrences, observations at current time
    model_def5 = @bugs begin
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
    ok5, _ = _gen_ok(model_def5, (I=3, T=10, sigma=0.7, sigma_y=0.3))
    @test ok5

    # 6) Inter-loop cycle (even/odd) requiring general fusion across separate loops -> reject
    model_def6 = @bugs begin
        sumX[1] = x[1]
        for i in 2:N
            sumX[i] = sumX[i - 1] + x[i]
        end
        for k in 1:div(N, 2)  # even indices
            x[2 * k] ~ Normal(sumX[2 * k - 1], tau)
        end
        for k in 1:(div(N, 2) - 1)  # odd indices
            x[2 * k + 1] ~ Gamma(sumX[2 * k], tau)
        end
    end
    ok6, _ = _gen_ok(
        model_def6, (N=10, tau=1.2, x=Union{Float64,Missing}[1.0; fill(missing, 9)])
    )
    @test !ok6

    # 7) Data-dependent indexing induces unknown/cyclic deps -> reject
    model_def7 = @bugs begin
        z[1] = 0.0
        z[2] = x[1] + 0.0
        y[1] = 0.0
        y[2] = x[3] + 0.0
        for i in 1:3
            x[i] = y[a[i]] + z[b[i]]
        end
    end
    ok7, _ = _gen_ok(model_def7, (a=[2, 2, 1], b=[2, 1, 2]))
    @test !ok7
end
