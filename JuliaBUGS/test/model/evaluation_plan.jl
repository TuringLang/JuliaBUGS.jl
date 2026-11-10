# The statement-grouped evaluation plan must give the same log densities and environment as
# visiting `sorted_nodes` one node at a time.

using JuliaBUGS: BangBang
using JuliaBUGS.Model:
    evaluate_with_values!!,
    _evaluate_with_values_in_sorted_order!!,
    _evaluation_plan_is_current,
    GraphEvaluationPlan,
    BUGSModel,
    set_evaluation_mode,
    UseGraph,
    UseGeneratedLogDensityFunction

function _plan_matches_reference(model, x; transformed=model.transformed, temperature=1.0)
    env_ref, ld_ref = _evaluate_with_values_in_sorted_order!!(
        model, x; transformed, temperature
    )
    env_new, ld_new = evaluate_with_values!!(model, x; transformed, temperature)
    same_env =
        keys(env_ref) == keys(env_new) && all(keys(env_ref)) do k
            isequal(env_ref[k], env_new[k]) && typeof(env_ref[k]) == typeof(env_new[k])
        end
    same_logp = all((:logprior, :loglikelihood, :tempered_logjoint)) do f
        isapprox(getfield(ld_ref, f), getfield(ld_new, f); rtol=1e-12, atol=1e-12)
    end
    return same_env && same_logp
end

@testset "Graph evaluation plan" begin
    @testset "bundled examples match the node-by-node evaluator" begin
        for name in (:rats, :pumps, :dogs, :seeds, :epil, :bones, :leuk, :eyes, :cervix)
            (; model_def, data, inits) = getfield(JuliaBUGS.BUGSExamples, name)
            model = compile(model_def, data, inits)
            @test _evaluation_plan_is_current(model.evaluation_plan, model)
            Base.invokelatest() do
                for transformed in (true, false)
                    m = JuliaBUGS.settrans(model, transformed)
                    x = JuliaBUGS.getparams(m)
                    @test _plan_matches_reference(m, x; transformed)
                    @test _plan_matches_reference(m, x; transformed, temperature=0.5)
                end
            end
        end
    end

    @testset "nodes of a statement share a run" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats
        model = compile(model_def, data, inits)
        n_nodes = length(model.graph_evaluation_data.sorted_nodes)
        @test length(model.evaluation_plan.runs) < 20 < n_nodes
    end

    @testset "chains stay in order and observations are deferred" begin
        model_def = @bugs begin
            x[1] ~ Normal(0, 1)
            for t in 2:T
                x[t] ~ Normal(0.5 * x[t - 1], 1)
            end
            for t in 1:T
                y[t] ~ Normal(x[t], 1)
            end
        end
        model = compile(model_def, (T=6, y=collect(1.0:6.0)))
        kinds = map(JuliaBUGS.Model._node_run_kind, model.evaluation_plan.runs)
        # x[1], then the chain x[2:T] in one run, then every observation in one run
        @test length(kinds) == 3
        @test kinds[end] === JuliaBUGS.Model.ObservationNodeRun
        Base.invokelatest() do
            x = randn(StableRNG(1), 6)
            @test _plan_matches_reference(model, x)
        end
    end

    @testset "integer fields widen as in the reference evaluator" begin
        # `z` is integer data with missing entries; in transformed space the latent entries
        # are read from the floating-point parameter vector.
        model_def = @bugs begin
            for i in 1:N
                z[i] ~ Categorical(w[1:2])
                y[i] ~ Normal(mu[z[i]], 1)
            end
            mu[1] ~ Normal(0, 1)
            mu[2] ~ Normal(3, 1)
        end
        data = (N=4, w=[0.3, 0.7], z=[2, missing, 1, missing], y=[2.5, 0.1, -0.3, 3.2])
        model = compile(model_def, data, (; z=[missing, 2, missing, 1]))
        @test model.evaluation_env.z isa Vector{Int}
        Base.invokelatest() do
            for transformed in (true, false)
                m = JuliaBUGS.settrans(model, transformed)
                x = JuliaBUGS.getparams(m)
                @test _plan_matches_reference(m, x; transformed)
            end
        end
    end

    @testset "the plan follows model changes" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.pumps
        model = compile(model_def, data, inits)

        # Changing only the environment's values reuses the plan.
        same = BUGSModel(model; evaluation_env=model.evaluation_env)
        @test same.evaluation_plan === model.evaluation_plan

        # Generated mode reorders `sorted_nodes`, which moves the parameter layout.
        generated = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
        graph = set_evaluation_mode(generated, UseGraph())
        @test _evaluation_plan_is_current(graph.evaluation_plan, graph)

        conditioned = JuliaBUGS.Model.condition(model, (; alpha=1.0))
        @test _evaluation_plan_is_current(conditioned.evaluation_plan, conditioned)
        fixed = JuliaBUGS.Model.fix(model, (; beta=1.0))
        @test _evaluation_plan_is_current(fixed.evaluation_plan, fixed)

        # A field replaced without the keyword constructor leaves the old plan behind; the
        # model then evaluates node by node instead of using it.
        stale = BangBang.setproperty!!(
            model, :graph_evaluation_data, generated.graph_evaluation_data
        )
        @test !_evaluation_plan_is_current(stale.evaluation_plan, stale)

        Base.invokelatest() do
            for m in (graph, conditioned, fixed, stale)
                @test _plan_matches_reference(m, JuliaBUGS.getparams(m))
            end
        end
    end

    @testset "gradients match the node-by-node evaluator" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats
        model = compile(model_def, data, inits)
        x = JuliaBUGS.getparams(model)
        Base.invokelatest() do
            reference(x) =
                last(_evaluate_with_values_in_sorted_order!!(model, x)).tempered_logjoint
            planned(x) = last(evaluate_with_values!!(model, x)).tempered_logjoint
            @test ForwardDiff.gradient(planned, x) ≈ ForwardDiff.gradient(reference, x)
            grad_model = JuliaBUGS.BUGSModelWithGradient(
                model, AutoMooncake(; config=nothing)
            )
            @test _evaluation_plan_is_current(
                grad_model.base_model.evaluation_plan, grad_model.base_model
            )
            logp, grad = LogDensityProblems.logdensity_and_gradient(grad_model, x)
            @test logp ≈ planned(x)
            @test grad ≈ ForwardDiff.gradient(reference, x)
        end
    end

    @testset "evaluation does not write into the model" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.dogs
        model = compile(model_def, data, inits)
        before = deepcopy(model.evaluation_env)
        Base.invokelatest() do
            evaluate_with_values!!(model, JuliaBUGS.getparams(model) .+ 0.1)
        end
        @test isequal(model.evaluation_env, before)
    end

    @testset "no node reads a value before it is computed" begin
        # Every value evaluation computes is first set to NaN. A node that ran before one of
        # its inputs (a missing graph edge) would read a NaN and change the log density.
        for name in (:rats, :seeds, :epil, :bones, :leuk, :birats)
            (; model_def, data, inits) = getfield(JuliaBUGS.BUGSExamples, name)
            model = compile(model_def, data, inits)
            gd = model.graph_evaluation_data
            env = deepcopy(model.evaluation_env)
            for (i, vn) in enumerate(gd.sorted_nodes)
                computed =
                    gd.variable_types[i] == JuliaBUGS.Model.TransformedParameter ||
                    gd.is_model_parameter_vals[i]
                computed || continue
                value = AbstractPPL.getvalue(env, vn)
                poisoned = if value isa AbstractFloat
                    oftype(value, NaN)
                elseif value isa AbstractArray{<:AbstractFloat}
                    fill!(similar(value), NaN)
                else
                    continue
                end
                env = BangBang.setindex!!(env, poisoned, vn)
            end
            poisoned_model = BUGSModel(model; evaluation_env=env)
            x = JuliaBUGS.getparams(model)
            Base.invokelatest() do
                expected = last(evaluate_with_values!!(model, x))
                actual = last(evaluate_with_values!!(poisoned_model, x))
                @test actual.logprior ≈ expected.logprior
                @test actual.loglikelihood ≈ expected.loglikelihood
            end
        end
    end
end
