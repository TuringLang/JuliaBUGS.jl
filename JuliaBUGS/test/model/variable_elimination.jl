# Variable elimination must give exactly what explicit enumeration of the discrete latents
# gives: evaluate the unmarginalized model with `UseGraph` for every configuration, then sum.

using JuliaBUGS: @bugs, compile, settrans, getparams, BangBang
using JuliaBUGS.Model:
    set_evaluation_mode,
    UseAutoMarginalization,
    UseGraph,
    evaluate_with_values!!,
    evaluate_with_marginalization_values!!

JuliaBUGS.@bugs_primitive Binomial

# log prior, log likelihood, and tempered log joint by summing over every configuration.
function _enumerated_log_densities(model, θ; temperature)
    graph_model = set_evaluation_mode(model, UseGraph())
    mc = model.marginalization_cache
    gd = graph_model.graph_evaluation_data
    latents = [
        i for i in eachindex(gd.sorted_nodes) if
        gd.is_model_parameter_vals[i] && mc.node_types[i] == :discrete_finite
    ]
    domains = map(latents) do i
        dist = gd.node_function_vals[i](graph_model.evaluation_env, gd.loop_vars_vals[i])
        collect(support(dist))
    end
    priors, joints = Any[], Any[]
    for config in Iterators.product(domains...)
        x = eltype(θ)[]
        for vn in gd.model_parameters
            k = findfirst(i -> gd.sorted_nodes[i] == vn, latents)
            if k === nothing
                offset = mc.param_offsets[vn]
                append!(x, θ[offset:(offset + mc.param_lengths[vn] - 1)])
            else
                push!(x, config[k])
            end
        end
        lds = last(evaluate_with_values!!(graph_model, x))
        push!(priors, lds.logprior)
        push!(joints, lds.logprior + lds.loglikelihood)
    end
    logprior = LogExpFunctions.logsumexp(priors)
    loglik = LogExpFunctions.logsumexp(joints) - logprior
    return (;
        logprior, loglikelihood=loglik, tempered_logjoint=logprior + temperature * loglik
    )
end

_marginalized(model) = set_evaluation_mode(settrans(model, true), UseAutoMarginalization())
_uses_elimination(model) = model.marginalization_cache.variable_elimination !== nothing

@testset "Variable elimination" begin
    hmm = @bugs begin
        for k in 1:K
            mu[k] ~ Normal(0, 10)
            A[k, 1:K] ~ Dirichlet(alpha[1:K])
        end
        sigma ~ Exponential(1)
        z[1] ~ Categorical(pi0[1:K])
        for t in 2:T
            z[t] ~ Categorical(A[z[t - 1], 1:K])
        end
        for t in 1:T
            y[t] ~ Normal(mu[z[t]], sigma)
        end
    end
    hmm_data = (K=3, T=4, alpha=ones(3), pi0=fill(1 / 3, 3), y=[-1.2, 0.3, 2.9, 3.1])

    mixture = @bugs begin
        w[1:2] ~ Dirichlet(alpha[1:2])
        mu[1] ~ Normal(-2, 5)
        mu[2] ~ Normal(2, 5)
        for i in 1:N
            z[i] ~ Categorical(w[1:2])
            y[i] ~ Normal(mu[z[i]], 1)
        end
    end
    mixture_data = (N=4, alpha=[2.0, 2.0], y=[-2.1, 1.7, 2.4, -1.5])

    # A Bernoulli latent used through arithmetic.
    bernoulli = @bugs begin
        p ~ Beta(1, 1)
        m ~ Normal(0, 5)
        for i in 1:N
            z[i] ~ Bernoulli(p)
            y[i] ~ Normal(z[i] * m, 1)
        end
    end
    bernoulli_data = (N=3, y=[0.1, 2.3, 1.9])

    # Two latents feeding one observation, and a continuous parameter depending on both.
    shared = @bugs begin
        u ~ Categorical(pu[1:2])
        v ~ Categorical(pv[1:2])
        a ~ Normal(m[u, v], 1)
        y ~ Normal(a + m[v, u], 1)
    end
    shared_data = (pu=[0.3, 0.7], pv=[0.6, 0.4], m=[-1.0 0.5; 1.5 3.0], y=0.8)

    # A latent's distribution reads another latent, and an observed discrete child.
    tree = @bugs begin
        r ~ Categorical(pr[1:2])
        for i in 1:2
            c[i] ~ Categorical(Q[r, 1:3])
            y[i] ~ Normal(c[i], s)
        end
        o ~ Categorical(Q[r, 1:3])
        s ~ Exponential(1)
    end
    tree_data = (pr=[0.4, 0.6], Q=[0.2 0.3 0.5; 0.6 0.3 0.1], y=[0.7, 2.6], o=3)

    # The value of `a` depends on `x` through its bijector.
    bounds = @bugs begin
        x ~ Categorical(p[1:2])
        a ~ Uniform(lo[x], hi[x])
        y ~ Normal(a, 1)
    end
    bounds_data = (p=[0.5, 0.5], lo=[0.0, 2.0], hi=[1.0, 5.0], y=1.5)

    cases = (
        ("hidden Markov model", hmm, hmm_data),
        ("mixture", mixture, mixture_data),
        ("Bernoulli latents", bernoulli, bernoulli_data),
        ("two latents into one observation", shared, shared_data),
        ("tree of latents", tree, tree_data),
        ("support depends on a latent", bounds, bounds_data),
    )

    @testset "$name matches enumeration" for (name, def, data) in cases
        model = _marginalized(compile(def, data))
        @test _uses_elimination(model)
        θ0 = getparams(model)
        Base.invokelatest() do
            for θ in (θ0, θ0 .+ 0.3, θ0 .- 0.4)
                expected = _enumerated_log_densities(model, θ; temperature=0.4)
                actual = last(
                    evaluate_with_marginalization_values!!(model, θ; temperature=0.4)
                )
                @test actual.logprior ≈ expected.logprior
                @test actual.loglikelihood ≈ expected.loglikelihood
                @test actual.tempered_logjoint ≈ expected.tempered_logjoint
            end
            reference(θ) =
                _enumerated_log_densities(model, θ; temperature=1.0).tempered_logjoint
            eliminated(θ) = LogDensityProblems.logdensity(model, θ)
            @test ForwardDiff.gradient(eliminated, θ0) ≈ ForwardDiff.gradient(reference, θ0)
        end
    end

    @testset "Mooncake gradient" begin
        model = _marginalized(compile(hmm, hmm_data))
        θ = getparams(model)
        Base.invokelatest() do
            grad_model = JuliaBUGS.BUGSModelWithGradient(
                model, AutoMooncake(; config=nothing)
            )
            _, grad = LogDensityProblems.logdensity_and_gradient(grad_model, θ)
            @test grad ≈
                ForwardDiff.gradient(t -> LogDensityProblems.logdensity(model, t), θ)
        end
    end

    @testset "a support that can change falls back to the frontier recursion" begin
        def = @bugs begin
            p ~ Beta(1, 1)
            k ~ Binomial(n, p)
            y ~ Normal(k, 1)
        end
        model = _marginalized(compile(def, (n=4, y=2.2)))
        @test !_uses_elimination(model)
        θ = getparams(model)
        Base.invokelatest() do
            expected = _enumerated_log_densities(model, θ; temperature=1.0)
            @test LogDensityProblems.logdensity(model, θ) ≈ expected.tempered_logjoint
        end
    end

    @testset "long chains do not overflow the stack" begin
        T = 3000
        def = @bugs begin
            z[1] ~ Categorical(p0[1:2])
            for t in 2:T
                z[t] ~ Categorical(A[z[t - 1], 1:2])
            end
            for t in 1:T
                y[t] ~ Normal(mu[z[t]], 1)
            end
        end
        data = (T=T, p0=[0.5, 0.5], A=[0.9 0.1; 0.2 0.8], mu=[-1.0, 1.0], y=sin.(1:T))
        model = _marginalized(compile(def, data))
        @test _uses_elimination(model)
        @test isfinite(Base.invokelatest(LogDensityProblems.logdensity, model, Float64[]))
    end
end
