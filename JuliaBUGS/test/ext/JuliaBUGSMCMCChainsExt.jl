# test the Chain construction with a simple Bayesian linear regression model
@testset "MCMCChains extension" begin
    model_def = @bugs begin
        # Likelihood
        for i in 1:N
            y[i] ~ dnorm(mu[i], tau)
            mu[i] = alpha + beta * x[i]
        end

        # Priors
        alpha ~ dnorm(0, 0.01)
        beta ~ dnorm(0, 0.01)
        sigma ~ dunif(0, 10)

        # Precision
        tau = pow(sigma, -2)

        # Generated Quantities for testing purposes
        gen_quant = alpha + beta * sigma
    end

    # ground truth: alpha = 3, beta = 2, sigma = 1
    data = (
        N=10,
        x=[0.0, 1.11, 2.22, 3.33, 4.44, 5.56, 6.67, 7.78, 8.89, 10.0],
        y=[1.58, 4.80, 7.10, 8.86, 11.73, 14.52, 18.22, 18.73, 21.04, 22.93],
    )

    model = compile(model_def, data, (;))
    ad_model = compile(model_def, data, (;); adtype=AutoReverseDiff(; compile=true))
    n_samples, n_adapts = 2000, 1000

    D = LogDensityProblems.dimension(ad_model)
    initial_θ = rand(D)

    hmc_chain = Base.invokelatest(
        AbstractMCMC.sample,
        ad_model,
        NUTS(0.8),
        n_samples;
        progress=false,
        chain_type=Chains,
        n_adapts=n_adapts,
        init_params=initial_θ,
        discard_initial=n_adapts,
    )
    @test hmc_chain.name_map[:parameters] == [
        :sigma
        :beta
        :alpha
        :gen_quant
    ]
    @test hmc_chain.name_map[:internals] == [
        :lp,
        :n_steps,
        :is_accept,
        :acceptance_rate,
        :log_density,
        :hamiltonian_energy,
        :hamiltonian_energy_error,
        :max_hamiltonian_energy_error,
        :tree_depth,
        :numerical_error,
        :step_size,
        :nom_step_size,
        :is_adapt,
    ]
    means = mean(hmc_chain)
    @test means[:alpha].nt.mean[1] ≈ 2.3 atol = 0.3
    @test means[:beta].nt.mean[1] ≈ 2.1 atol = 0.3
    @test means[:sigma].nt.mean[1] ≈ 0.9 atol = 0.3
    @test means[:gen_quant].nt.mean[1] ≈ 4.2 atol = 0.3

    n_samples, n_adapts = 20000, 5000

    mh_chain = AbstractMCMC.sample(
        model,
        RWMH(MvNormal(zeros(D), I)),
        n_samples;
        progress=false,
        chain_type=Chains,
        n_adapts=n_adapts,
        init_params=initial_θ,
        discard_initial=n_adapts,
    )

    @test mh_chain.name_map[:parameters] == [
        :sigma
        :beta
        :alpha
        :gen_quant
    ]
    @test mh_chain.name_map[:internals] == [:lp, :accepted]
    means = mean(mh_chain)
    @test means[:alpha].nt.mean[1] ≈ 2.3 atol = 0.3
    @test means[:beta].nt.mean[1] ≈ 2.1 atol = 0.3
    @test means[:sigma].nt.mean[1] ≈ 0.9 atol = 0.3
    @test means[:gen_quant].nt.mean[1] ≈ 4.2 atol = 0.3

    # test for more complicated varnames
    model_def = @bugs begin
        A[1, 1:3] ~ Dirichlet(ones(3))
        A[2, 1:3] ~ Dirichlet(ones(3))
        A[3, 1:3] ~ Dirichlet(ones(3))

        mu[1:3] ~ MvNormal(zeros(3), 10 * Diagonal(ones(3)))
        sigma[1] ~ InverseGamma(2, 3)
        sigma[2] ~ InverseGamma(2, 3)
        sigma[3] ~ InverseGamma(2, 3)
    end
    ad_model = compile(model_def, (;); adtype=AutoReverseDiff(; compile=true))
    hmc_chain = AbstractMCMC.sample(
        ad_model, NUTS(0.8), 10; progress=false, chain_type=Chains
    )
    @test Set(hmc_chain.name_map[:parameters]) == Set([
        Symbol("sigma[3]"),
        Symbol("sigma[2]"),
        Symbol("sigma[1]"),
        Symbol("mu[1:3][1]"),
        Symbol("mu[1:3][2]"),
        Symbol("mu[1:3][3]"),
        Symbol("A[3, 1:3][1]"),
        Symbol("A[3, 1:3][2]"),
        Symbol("A[3, 1:3][3]"),
        Symbol("A[2, 1:3][1]"),
        Symbol("A[2, 1:3][2]"),
        Symbol("A[2, 1:3][3]"),
        Symbol("A[1, 1:3][1]"),
        Symbol("A[1, 1:3][2]"),
        Symbol("A[1, 1:3][3]"),
    ])
end

@testset "forward-sampled generated quantities in chains" begin
    model_def = @bugs begin
        mu ~ dnorm(0, 1)
        y ~ dnorm(mu, 1)
        z ~ dnorm(mu, 1)      # stochastic generated quantity
        pred = mu + 1.0       # deterministic generated quantity
    end
    model = compile(model_def, (; y=0.5))
    @test LogDensityProblems.dimension(model) == 1

    # Synthetic posterior draws of the single model parameter `mu`.
    samples = [[m] for m in range(-1.0, 1.0; length=25)]
    chn = JuliaBUGS.gen_chains(model, samples, []; rng=StableRNG(2024))

    colnames = names(chn)
    @test :mu in colnames
    @test :z in colnames       # stochastic generated quantity surfaced
    @test :pred in colnames    # deterministic generated quantity surfaced

    A = Array(chn)
    mucol = A[:, findfirst(==(:mu), colnames)]
    zcol = A[:, findfirst(==(:z), colnames)]
    predcol = A[:, findfirst(==(:pred), colnames)]

    # Stochastic generated quantity is forward-sampled, not frozen at one value.
    @test length(unique(zcol)) > 1
    # Deterministic generated quantity equals f(model parameter) for every draw.
    @test all(predcol .≈ mucol .+ 1.0)
    # Model-parameter column matches the synthetic samples in order.
    @test mucol ≈ [s[1] for s in samples]
end

@testset "chains use cached generated-quantity classification" begin
    # Even without any observations, a terminal deterministic node that feeds no
    # stochastic factor is a generated quantity; the stochastic node remains a model
    # parameter. `gen_chains` reads the cached classification, so this guards against
    # the cached generated-quantity set dropping terminal deterministic nodes.
    model_def = @bugs begin
        x ~ dnorm(0, 1)
        pred = x + 1.0
    end
    model = compile(model_def, (;))

    @test !isempty(JuliaBUGS.Model.generated_quantities(model))

    samples = [[-0.5], [0.5]]
    chn = JuliaBUGS.gen_chains(model, samples, []; rng=StableRNG(2024))

    colnames = names(chn)
    @test :x in colnames
    @test :pred in colnames
end

@testset "auto-marginalized chains reconstruct generated quantities from samples" begin
    model_def = @bugs begin
        mu ~ Normal(0, 1)
        z ~ Categorical(w[1:2])
        y ~ Normal(mu + z, 1)
        pred = mu + 1.0
    end

    model = compile(model_def, (; w=[0.5, 0.5], y=1.0))
    model = JuliaBUGS.settrans(model, true)
    model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseAutoMarginalization())
    @test LogDensityProblems.dimension(model) == 1

    samples = [[m] for m in range(-1.0, 1.0; length=25)]
    chn = JuliaBUGS.gen_chains(model, samples, []; rng=StableRNG(2024))

    colnames = names(chn)
    @test :mu in colnames
    @test :z in colnames       # recovered marginalized latent
    @test :pred in colnames    # deterministic generated quantity

    A = Array(chn)
    mucol = A[:, findfirst(==(:mu), colnames)]
    zcol = A[:, findfirst(==(:z), colnames)]
    predcol = A[:, findfirst(==(:pred), colnames)]

    @test mucol ≈ [s[1] for s in samples]
    @test predcol ≈ mucol .+ 1.0
    @test all(z -> z in (1, 2), zcol)
end

@testset "from_samples converts ParamsWithStats draws" begin
    model_def = @bugs begin
        x[1:2] ~ dmnorm(m[1:2], tau[1:2, 1:2])
        y ~ dnorm(x[1] + x[2], 1)
        total = x[1] + x[2]
    end
    model = compile(model_def, (m=[0.0, 0.0], tau=[1.0 0.0; 0.0 1.0], y=0.5))

    draws = Base.invokelatest(
        AbstractMCMC.sample,
        StableRNG(11),
        model,
        JuliaBUGS.IndependentMH(),
        10;
        progress=false,
        chain_type=Vector{AbstractMCMC.ParamsWithStats},
    )
    chn = AbstractMCMC.from_samples(Chains, reshape(draws, :, 1))

    @test chn isa Chains
    # Two parameter columns, one generated quantity, and `lp`.
    @test size(chn) == (10, 4, 1)
    @test chn.name_map[:internals] == [:lp]
    # Array-valued variables are flattened into one column per element, named after the
    # leaf `VarName` exactly as `gen_chains` names them.
    @test Set(chn.name_map[:parameters]) ==
        Set([Symbol("x[1:2][1]"), Symbol("x[1:2][2]"), :total])
    @test vec(chn[Symbol("x[1:2][1]")].data) ≈
        [d.params[@varname(x[1:2])][1] for d in draws]
    @test vec(chn[:total].data) ≈ [d.params[@varname(total)] for d in draws]
end

@testset "from_samples flattens array-valued statistics" begin
    model_def = @bugs begin
        a ~ dnorm(0, 1)
        b ~ dnorm(0, 1)
        y ~ dnorm(a + b, 1)
    end
    model = compile(model_def, (; y=0.5), (; a=0.0, b=0.0))

    # A multivariate slice sampler reports `num_proposals` per coordinate, so the statistic
    # is an array. The initial transition reports no `num_proposals` at all.
    draws = Base.invokelatest(
        AbstractMCMC.sample,
        StableRNG(31),
        model,
        SliceSampling.RandPermGibbs(SliceSampling.SliceSteppingOut(1.0)),
        12;
        progress=false,
        chain_type=Vector{AbstractMCMC.ParamsWithStats},
    )
    @test keys(draws[1].stats) == (:lp,)
    @test draws[2].stats.num_proposals isa AbstractArray

    chn = AbstractMCMC.from_samples(Chains, reshape(draws, :, 1))
    @test chn.name_map[:internals] ==
        [:lp, Symbol("num_proposals[1]"), Symbol("num_proposals[2]")]
    # Draws that never reported the statistic get `NaN` in its columns.
    column = vec(chn[Symbol("num_proposals[1]")].data)
    @test isnan(column[1])
    @test column[2:end] == [d.stats.num_proposals[1] for d in draws[2:end]]
end

@testset "from_samples matches sampling straight to Chains" begin
    model_def = @bugs begin
        mu ~ dnorm(0, 1)
        for i in 1:N
            y[i] ~ dnorm(mu, 1)
        end
        doubled = 2 * mu
    end
    model = compile(model_def, (N=3, y=[1.2, 0.8, 1.5]), (; mu=0.0))

    direct = Base.invokelatest(
        AbstractMCMC.sample,
        StableRNG(77),
        model,
        JuliaBUGS.IndependentMH(),
        15;
        progress=false,
        chain_type=Chains,
        discard_initial=5,
        rng=StableRNG(404),
    )
    draws = Base.invokelatest(
        AbstractMCMC.sample,
        StableRNG(77),
        model,
        JuliaBUGS.IndependentMH(),
        15;
        progress=false,
        chain_type=Vector{AbstractMCMC.ParamsWithStats},
        discard_initial=5,
        rng=StableRNG(404),
    )
    converted = AbstractMCMC.from_samples(Chains, reshape(draws, :, 1); start=6)

    @test names(converted) == names(direct)
    @test converted.name_map == direct.name_map
    @test Array(converted) == Array(direct)
    # A plain vector carries no iteration indices, so `start` restores them.
    @test range(converted) == range(direct)
end

@testset "from_samples over multiple chains" begin
    model_def = @bugs begin
        mu ~ dnorm(0, 1)
        y ~ dnorm(mu, 1)
    end
    model = compile(model_def, (; y=0.4), (; mu=0.0))

    chains = Base.invokelatest(
        AbstractMCMC.sample,
        StableRNG(55),
        model,
        JuliaBUGS.IndependentMH(),
        MCMCSerial(),
        8,
        3;
        progress=false,
        chain_type=Vector{AbstractMCMC.ParamsWithStats},
    )
    chn = AbstractMCMC.from_samples(Chains, reduce(hcat, chains))

    @test size(chn) == (8, 2, 3)
    @test vec(chn[:mu].data[:, 2]) ≈ [d.params[@varname(mu)] for d in chains[2]]
end

@testset "MALA draws are named after the model" begin
    model_def = @bugs begin
        mu ~ dnorm(0, 1)
        y ~ dnorm(mu, 1)
    end
    model = compile(model_def, (; y=0.4), (; mu=0.0); adtype=AutoReverseDiff())

    chn = Base.invokelatest(
        AbstractMCMC.sample,
        StableRNG(66),
        model,
        AdvancedMH.MALA(g -> MvNormal(0.1 .* g, 0.2 * LinearAlgebra.I)),
        12;
        progress=false,
        chain_type=Chains,
        initial_params=[0.0],
    )

    @test chn.name_map[:parameters] == [:mu]
    @test chn.name_map[:internals] == [:lp, :accepted]
end

@testset "from_samples unions statistic layouts across draws" begin
    params() = JuliaBUGS.Model.ParamsDict(@varname(mu) => 1.0)
    draws = [
        AbstractMCMC.ParamsWithStats(params(), (lp=-1.0, np=[1, 2], note=:warmup)),
        AbstractMCMC.ParamsWithStats(params(), (lp=-2.0, np=[3, 4, 5])),
        AbstractMCMC.ParamsWithStats(params(), (lp=-3.0, np=6.0)),
    ]
    chn = AbstractMCMC.from_samples(Chains, reshape(draws, :, 1))

    # Columns are the union of (key, index) pairs in first-seen order; `note` is never a
    # real number, so it gets no column.
    @test chn.name_map[:internals] ==
        [:lp, Symbol("np[1]"), Symbol("np[2]"), Symbol("np[3]"), :np]
    @test all(isequal.(vec(chn[Symbol("np[1]")].data), [1.0, 3.0, NaN]))
    @test all(isequal.(vec(chn[Symbol("np[3]")].data), [NaN, 5.0, NaN]))
    @test all(isequal.(vec(chn[:np].data), [NaN, NaN, 6.0]))
end

@testset "from_samples is independent of dict insertion order" begin
    a = JuliaBUGS.Model.ParamsDict(@varname(mu) => 1.0, @varname(tau) => 2.0)
    b = JuliaBUGS.Model.ParamsDict(@varname(tau) => 20.0, @varname(mu) => 10.0)
    draws = [
        AbstractMCMC.ParamsWithStats(a, NamedTuple()),
        AbstractMCMC.ParamsWithStats(b, NamedTuple()),
    ]
    chn = AbstractMCMC.from_samples(Chains, reshape(draws, :, 1))

    @test vec(chn[:mu].data) == [1.0, 10.0]
    @test vec(chn[:tau].data) == [2.0, 20.0]

    missing_key = JuliaBUGS.Model.ParamsDict(@varname(mu) => 1.0, @varname(sig) => 0.5)
    bad = [draws[1], AbstractMCMC.ParamsWithStats(missing_key, NamedTuple())]
    @test_throws KeyError AbstractMCMC.from_samples(Chains, reshape(bad, :, 1))
end
