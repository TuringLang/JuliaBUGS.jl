using Test
using JuliaBUGS
using JuliaBUGS.Melding
using JuliaBUGS.Melding: LinkInfo, marginal_exponents, needs_all_marginals, logpool_extra
using JuliaBUGS.Model:
    getparams,
    initialize!,
    model_parameters,
    settrans,
    variable_type,
    GeneratedQuantity,
    ModelParameter
using AbstractPPL: @varname
using AbstractMCMC
using ADTypes
using AdvancedHMC
using DifferentiationInterface
using Distributions
using ForwardDiff
using LogDensityProblems
using Random
using ReverseDiff
using StableRNGs
using Statistics

JuliaBUGS.@bugs_primitive Normal Gamma LogNormal MvNormal exp sqrt sum

# Parameter vector of `model` at the constrained values in `nt`, in the model's own
# (transformed) parameterisation. Entries of `nt` the model does not have are ignored.
function params_at(model, nt)
    return getparams(initialize!(model, nt))
end
params_at(mm::MeldedModel, nt) = reduce(vcat, (params_at(pm, nt) for pm in mm.prepared))

@testset "Markov melding" begin
    rng = StableRNG(20191)

    # Two submodels with a common root link `phi`, and the joint model they were split from.
    sub1_def = @bugs begin
        phi ~ Normal(0, 1)
        tau ~ Gamma(2, 1)
        for i in 1:3
            y[i] ~ Normal(phi, 1 / sqrt(tau))
        end
    end
    sub2_def = @bugs begin
        phi ~ Normal(0, 1)
        gam ~ Normal(0, 1)
        for j in 1:2
            x[j] ~ Normal(phi * gam, 1)
        end
    end
    joint_def = @bugs begin
        phi ~ Normal(0, 1)
        tau ~ Gamma(2, 1)
        for i in 1:3
            y[i] ~ Normal(phi, 1 / sqrt(tau))
        end
        gam ~ Normal(0, 1)
        for j in 1:2
            x[j] ~ Normal(phi * gam, 1)
        end
    end
    y = [0.3, -0.2, 1.1]
    x = [0.5, 0.7]
    sub1 = sub1_def((; y))
    sub2 = sub2_def((; x))
    joint = joint_def((; y, x))
    random_point(rng) = (; phi=randn(rng), tau=rand(rng, Gamma(2, 1)), gam=randn(rng))

    @testset "pooling bookkeeping" begin
        @test marginal_exponents(ProductOfExperts(), 3) == zeros(3)
        @test marginal_exponents(Dictatorial(2), 3) == [-1.0, 0.0, -1.0]
        @test marginal_exponents(LogarithmicPooling([1.0, 0.5, 0.0]), 3) ==
            [0.0, -0.5, -1.0]
        @test marginal_exponents(LinearPooling([1, 3]), 2) == [-1.0, -1.0]
        @test LinearPooling([1, 3]).weights ≈ [0.25, 0.75]
        @test !needs_all_marginals(ProductOfExperts())
        @test needs_all_marginals(LinearPooling([0.5, 0.5]))
        @test logpool_extra(LinearPooling([0.5, 0.5]), [log(2.0), log(4.0)]) ≈ log(3.0)
        @test logpool_extra(Dictatorial(1), [1.0, 2.0]) == 0.0
        @test_throws ArgumentError Dictatorial(0)
        @test_throws ArgumentError LogarithmicPooling([1.0, -0.1])
        @test_throws ArgumentError LinearPooling([0.0, 0.0])
    end

    @testset "closed link: pointwise agreement with the joint model" begin
        # With identical priors on `phi`, every pooling rule except product of experts
        # reproduces the joint exactly; product of experts multiplies in the prior twice.
        cases = [
            (Dictatorial(1), nt -> 0.0, [:carrier, :fixed]),
            (Dictatorial(2), nt -> 0.0, [:fixed, :carrier]),
            (
                ProductOfExperts(),
                nt -> logpdf(Normal(0, 1), nt.phi),
                [:carrier, :conditioned],
            ),
            (LogarithmicPooling([0.5, 0.5]), nt -> 0.0, [:carrier, :conditioned]),
            (
                LogarithmicPooling([1.0, 1.0]),
                nt -> logpdf(Normal(0, 1), nt.phi),
                [:carrier, :conditioned],
            ),
            (LogarithmicPooling([1.0, 0.0]), nt -> 0.0, [:carrier, :fixed]),
            (LinearPooling([0.3, 0.7]), nt -> 0.0, [:carrier, :fixed]),
        ]
        for (pooling, extra, roles) in cases
            mm = meld([sub1, sub2], [:phi, :phi]; pooling)
            @test mm.roles == roles
            @test LogDensityProblems.dimension(mm) == 3
            @test LogDensityProblems.dimension(joint) == 3
            for _ in 1:5
                nt = random_point(rng)
                lp_meld = LogDensityProblems.logdensity(mm, params_at(mm, nt))
                lp_joint = LogDensityProblems.logdensity(joint, params_at(joint, nt))
                @test lp_meld ≈ lp_joint + extra(nt) atol = 1e-10
            end
        end
    end

    @testset "closed link: hand-written densities" begin
        a_def = @bugs begin
            phi ~ Normal(0, 1)
            y ~ Normal(phi, 1)
        end
        b_def = @bugs begin
            phi ~ Normal(1, 2)
            x ~ Normal(phi, 1)
        end
        a = a_def((; y=0.8))
        b = b_def((; x=-0.4))
        lik(φ) = logpdf(Normal(φ, 1), 0.8) + logpdf(Normal(φ, 1), -0.4)
        pa(φ) = logpdf(Normal(0, 1), φ)
        pb(φ) = logpdf(Normal(1, 2), φ)
        expected = Dict(
            ProductOfExperts() => φ -> pa(φ) + pb(φ) + lik(φ),
            Dictatorial(1) => φ -> pa(φ) + lik(φ),
            Dictatorial(2) => φ -> pb(φ) + lik(φ),
            LogarithmicPooling([0.3, 0.6]) => φ -> 0.3 * pa(φ) + 0.6 * pb(φ) + lik(φ),
            LinearPooling([0.25, 0.75]) =>
                φ -> log(0.25 * exp(pa(φ)) + 0.75 * exp(pb(φ))) + lik(φ),
        )
        for (pooling, f) in expected
            mm = meld([a, b], [:phi, :phi]; pooling)
            @test LogDensityProblems.dimension(mm) == 1
            for φ in (-1.3, 0.0, 0.7, 2.5)
                @test LogDensityProblems.logdensity(mm, [φ]) ≈ f(φ) atol = 1e-12
            end
        end
        # The link is read back consistently into every submodel.
        mm = meld([a, b], [:phi, :phi])
        envs = evaluation_envs(mm, [0.7])
        @test envs[1].phi == 0.7
        @test envs[2].phi == 0.7
        @test Melding.link_value(mm, [0.7]) == [0.7]
        @test parameter_names(mm) == [(1, @varname(phi))]
    end

    @testset "logical link: one submodel defines the link deterministically" begin
        own_def = @bugs begin
            theta ~ Normal(0, 1)
            phi = exp(theta)
            y ~ Normal(theta, 1)
        end
        oth_def = @bugs begin
            phi ~ LogNormal(0, 1)
            x ~ Normal(phi, 1)
        end
        jl_def = @bugs begin
            theta ~ Normal(0, 1)
            phi = exp(theta)
            y ~ Normal(theta, 1)
            x ~ Normal(phi, 1)
        end
        own = own_def((; y=0.4))
        oth = oth_def((; x=1.2))
        jl = jl_def((; y=0.4, x=1.2))
        # `phi` has no observed descendant in `own`, so it is a generated quantity there and
        # must be recomputed by the melded model.
        @test variable_type(own, @varname(phi)) == GeneratedQuantity

        mo = meld([own, oth], [:phi, :phi]; pooling=Dictatorial(1))
        @test mo.carrier == 1
        @test mo.roles == [:carrier, :fixed]
        @test mo.links[1].kind == :logical
        for θ in (-1.0, 0.2, 1.5)
            @test LogDensityProblems.logdensity(mo, [θ]) ≈
                LogDensityProblems.logdensity(jl, [θ]) atol = 1e-12
            @test Melding.link_value(mo, [θ]) ≈ [exp(θ)]
        end

        # The implied prior of `phi` under `own` is LogNormal(0, 1), the same as under `oth`,
        # so dictatorial pooling towards `oth` also reproduces the joint, given that marginal.
        @test_throws ArgumentError meld([own, oth], [:phi, :phi]; pooling=Dictatorial(2))
        mo2 = meld(
            [own, oth],
            [:phi, :phi];
            pooling=Dictatorial(2),
            marginals=Dict(1 => LogNormal(0, 1)),
        )
        @test mo2.carrier == 1
        @test mo2.roles == [:carrier, :conditioned]
        for θ in (-1.0, 0.2, 1.5)
            @test LogDensityProblems.logdensity(mo2, [θ]) ≈
                LogDensityProblems.logdensity(jl, [θ]) atol = 1e-12
        end
        mo3 = meld(
            [own, oth],
            [:phi, :phi];
            pooling=Dictatorial(2),
            marginals=Dict(1 => FunctionMarginal(φ -> logpdf(LogNormal(0, 1), φ))),
        )
        @test LogDensityProblems.logdensity(mo3, [0.2]) ≈
            LogDensityProblems.logdensity(jl, [0.2])

        @testset "simulated marginal" begin
            grid = exp.(range(-1.5, 1.5; length=7))
            exact = [logpdf(LogNormal(0, 1), g) for g in grid]
            kde = SimulatedMarginal(own, :phi; n=20_000, rng, transform=log)
            @test kde.n == 20_000
            @test maximum(abs, [logmarginal(kde, [g]) for g in grid] .- exact) < 0.1
            nrm = SimulatedMarginal(
                own, :phi; n=20_000, rng, transform=log, estimator=:normal
            )
            @test nrm.density isa Normal
            @test maximum(abs, [logmarginal(nrm, [g]) for g in grid] .- exact) < 0.1
            # Fitting from a matrix of draws, and on the identity scale.
            draws = exp.(randn(rng, 1, 5_000))
            m3 = SimulatedMarginal(draws; transform=log, estimator=:normal)
            @test abs(logmarginal(m3, [1.0]) - exact[4]) < 0.1
            m4 = SimulatedMarginal(randn(rng, 1, 5_000); estimator=:normal)
            @test abs(logmarginal(m4, [0.3]) - logpdf(Normal(0, 1), 0.3)) < 0.1
            @test_throws ArgumentError SimulatedMarginal(draws; estimator=:spline)
            # A transform that does not match the support is rejected.
            @test_throws ArgumentError SimulatedMarginal(randn(rng, 1, 100); transform=log)
            # Melding with the estimate stays close to the joint.
            mo4 = meld(
                [own, oth], [:phi, :phi]; pooling=Dictatorial(2), marginals=Dict(1 => nrm)
            )
            @test abs(
                LogDensityProblems.logdensity(mo4, [0.2]) -
                LogDensityProblems.logdensity(jl, [0.2]),
            ) < 0.1
        end
    end

    @testset "multivariate link" begin
        v1_def = @bugs begin
            for k in 1:2
                phi[k] ~ Normal(0, 1)
            end
            for i in 1:3
                y[i] ~ Normal(phi[1] + phi[2] * i, 1)
            end
        end
        v2_def = @bugs begin
            for k in 1:2
                phi[k] ~ Normal(0, 1)
            end
            x ~ Normal(phi[1] * phi[2], 1)
        end
        vj_def = @bugs begin
            for k in 1:2
                phi[k] ~ Normal(0, 1)
            end
            for i in 1:3
                y[i] ~ Normal(phi[1] + phi[2] * i, 1)
            end
            x ~ Normal(phi[1] * phi[2], 1)
        end
        yv = [0.1, 0.4, 0.9]
        v1 = v1_def((; y=yv))
        v2 = v2_def((; x=0.3))
        vj = vj_def((; y=yv, x=0.3))
        explicit = [@varname(phi[1]), @varname(phi[2])]
        for links in ([:phi, :phi], [explicit, explicit], [@varname(phi), explicit])
            mm = meld([v1, v2], links; pooling=Dictatorial(2))
            @test mm.links[1].nodes == explicit
            @test mm.links[1].length == 2
            @test LogDensityProblems.dimension(mm) == 2
            for _ in 1:3
                nt = (; phi=randn(rng, 2))
                @test LogDensityProblems.logdensity(mm, params_at(mm, nt)) ≈
                    LogDensityProblems.logdensity(vj, params_at(vj, nt)) atol = 1e-10
            end
            # Array-valued link nodes are written into copies, never into the shared env.
            before = copy(mm.prepared[1].evaluation_env.phi)
            LogDensityProblems.logdensity(mm, [0.9, -0.9])
            @test mm.prepared[1].evaluation_env.phi == before
        end
        # Order of the nodes follows the specification, and lengths must agree.
        mm = meld(
            [v1, v2],
            [[@varname(phi[2]), @varname(phi[1])], explicit];
            pooling=Dictatorial(2),
        )
        @test mm.links[1].nodes == [@varname(phi[2]), @varname(phi[1])]
        @test_throws ArgumentError meld([v1, v2], [@varname(phi[1]), explicit])
    end

    @testset "open link: the link has a stochastic parent" begin
        o1_def = @bugs begin
            mu ~ Normal(0, 1)
            phi ~ Normal(mu, 1)
            y ~ Normal(phi, 1)
        end
        o2_def = @bugs begin
            phi ~ Normal(0, sqrt(2))   # equals the prior marginal of phi under o1
            x ~ Normal(phi, 1)
        end
        oj_def = @bugs begin
            mu ~ Normal(0, 1)
            phi ~ Normal(mu, 1)
            y ~ Normal(phi, 1)
            x ~ Normal(phi, 1)
        end
        o1 = o1_def((; y=0.5))
        o2 = o2_def((; x=-0.5))
        oj = oj_def((; y=0.5, x=-0.5))
        m1 = meld([o1, o2], [:phi, :phi]; pooling=Dictatorial(1))
        @test m1.links[1].kind == :open
        @test m1.roles == [:carrier, :fixed]
        # Towards the open submodel, fixing is not available: the marginal must be supplied.
        @test_throws ArgumentError meld([o1, o2], [:phi, :phi]; pooling=Dictatorial(2))
        m2 = meld(
            [o1, o2],
            [:phi, :phi];
            pooling=Dictatorial(2),
            marginals=Dict(1 => Normal(0, sqrt(2))),
        )
        @test m2.roles == [:conditioned, :carrier]
        @test @varname(mu) in model_parameters(m2.prepared[1])
        for _ in 1:4
            nt = (; mu=randn(rng), phi=randn(rng))
            lp_joint = LogDensityProblems.logdensity(oj, params_at(oj, nt))
            @test LogDensityProblems.logdensity(m1, params_at(m1, nt)) ≈ lp_joint atol =
                1e-10
            @test LogDensityProblems.logdensity(m2, params_at(m2, nt)) ≈ lp_joint atol =
                1e-10
        end
        @test_throws ArgumentError ExactMarginal(o1, :phi)
        @test ExactMarginal(o2, :phi) isa ExactMarginal
        @test logmarginal(ExactMarginal(o2, :phi), [0.3]) ≈ logpdf(Normal(0, sqrt(2)), 0.3)
    end

    @testset "submodels without data, and links without observed descendants" begin
        d_def = @bugs begin
            phi ~ Normal(0, 1)
            y ~ Normal(phi, 1)
        end
        # A prior-only submodel: all its stochastic nodes are model parameters.
        prior_def = @bugs begin
            phi ~ Normal(0, 1)
            gam ~ Normal(phi, 1)
        end
        # A submodel with data that does not depend on the link.
        gq_def = @bugs begin
            phi ~ Normal(0, 1)
            gam ~ Normal(0, 1)
            x ~ Normal(gam, 1)
        end
        d = d_def((; y=0.2))
        prior_only = prior_def((;))
        gq = gq_def((; x=0.9))
        @test variable_type(gq, @varname(phi)) == GeneratedQuantity

        mp = meld([d, prior_only], [:phi, :phi]; pooling=Dictatorial(1))
        @test mp.roles == [:carrier, :fixed]
        for (φ, γ) in ((0.1, 0.4), (-0.7, 1.3))
            @test LogDensityProblems.logdensity(mp, [φ, γ]) ≈
                logpdf(Normal(0, 1), φ) +
                  logpdf(Normal(φ, 1), 0.2) +
                  logpdf(Normal(φ, 1), γ)
        end

        # Product of experts conditions `gq` on the link, which keeps its prior factor.
        mg = meld([d, gq], [:phi, :phi])
        @test mg.carrier == 1
        @test mg.roles == [:carrier, :conditioned]
        for (φ, γ) in ((0.1, 0.4), (-0.7, 1.3))
            @test LogDensityProblems.logdensity(mg, [φ, γ]) ≈
                2 * logpdf(Normal(0, 1), φ) +
                  logpdf(Normal(φ, 1), 0.2) +
                  logpdf(Normal(0, 1), γ) +
                  logpdf(Normal(γ, 1), 0.9)
        end
        # The carrier is never a submodel in which the link is a generated quantity.
        mg2 = meld([gq, d], [:phi, :phi]; pooling=Dictatorial(1))
        @test mg2.carrier == 2
        @test mg2.roles == [:conditioned, :carrier]
        @test mg2.exponents == [0.0, -1.0]
        @test mg2.marginals[2] isa ExactMarginal
        @test_throws ArgumentError meld([gq, gq], [:phi, :phi])
    end

    @testset "transformed and untransformed parameterisations agree" begin
        mm_t = meld([sub1, sub2], [:phi, :phi]; pooling=Dictatorial(1))
        mm_u = meld(
            [settrans(sub1, false), settrans(sub2, false)],
            [:phi, :phi];
            pooling=Dictatorial(1),
        )
        joint_u = settrans(joint, false)
        @test_throws ArgumentError meld([sub1, settrans(sub2, false)], [:phi, :phi])
        for _ in 1:3
            nt = random_point(rng)
            d_meld =
                LogDensityProblems.logdensity(mm_t, params_at(mm_t, nt)) -
                LogDensityProblems.logdensity(mm_u, params_at(mm_u, nt))
            d_joint =
                LogDensityProblems.logdensity(joint, params_at(joint, nt)) -
                LogDensityProblems.logdensity(joint_u, params_at(joint_u, nt))
            @test d_meld ≈ d_joint atol = 1e-10
            @test d_meld ≈ log(nt.tau) atol = 1e-10   # the Jacobian of log(tau), once
        end
    end

    @testset "gradients" begin
        mm = meld([sub1, sub2], [:phi, :phi]; pooling=LinearPooling([0.4, 0.6]))
        f(xv) = LogDensityProblems.logdensity(mm, xv)
        x0 = params_at(mm, random_point(rng))
        g_fd = ForwardDiff.gradient(f, x0)
        h = 1e-6
        unit(k) = [i == k ? 1.0 : 0.0 for i in 1:3]
        g_num = [(f(x0 + h * unit(k)) - f(x0 - h * unit(k))) / 2h for k in 1:3]
        @test g_fd ≈ g_num atol = 1e-5
        for adtype in (AutoForwardDiff(), AutoReverseDiff())
            gm = MeldedModelWithGradient(mm, adtype)
            @test LogDensityProblems.capabilities(typeof(gm)) ==
                LogDensityProblems.LogDensityOrder{1}()
            @test LogDensityProblems.dimension(gm) == 3
            lp, g = LogDensityProblems.logdensity_and_gradient(gm, x0)
            @test lp ≈ f(x0)
            @test g ≈ g_fd atol = 1e-8
            @test getparams(gm) == getparams(mm)
        end
        # Out-of-support points are rejected, not raised.
        bad = params_at(mm, random_point(rng))
        @test isfinite(LogDensityProblems.logdensity(mm, bad))
    end

    @testset "sampling a conjugate case with NUTS" begin
        c1_def = @bugs begin
            phi ~ Normal(0, 1)
            for i in 1:4
                y[i] ~ Normal(phi, 1)
            end
        end
        c2_def = @bugs begin
            phi ~ Normal(0, 1)
            for j in 1:4
                x[j] ~ Normal(phi, 1)
            end
        end
        yc = [2.9, 3.4, 2.6, 3.1]
        xc = [3.3, 2.8, 3.0, 3.5]
        c1 = c1_def((; y=yc))
        c2 = c2_def((; x=xc))
        S = sum(yc) + sum(xc)
        # Dictatorial pooling keeps one Normal(0, 1) prior; product of experts keeps two,
        # which is a Normal(0, 1/sqrt(2)) prior. Both posteriors are Normal.
        for (pooling, prec) in ((Dictatorial(1), 1 + 8), (ProductOfExperts(), 2 + 8))
            mm = meld([c1, c2], [:phi, :phi]; pooling)
            chain = AbstractMCMC.sample(
                StableRNG(7),
                mm,
                NUTS(0.8),
                2_000;
                adtype=AutoForwardDiff(),
                n_adapts=500,
                discard_initial=500,
                progress=false,
            )
            draws = [t.z.θ[1] for t in chain]
            @test mean(draws) ≈ S / prec atol = 0.06
            @test std(draws) ≈ 1 / sqrt(prec) atol = 0.06
            envs = evaluation_envs(mm, chain[end].z.θ)
            @test envs[1].phi == envs[2].phi
        end
    end

    @testset "long array links expand in column-major index order" begin
        # With twelve elements, string order would put phi[10] before phi[2].
        a_def = @bugs begin
            for i in 1:12
                phi[i] ~ Normal(0, 1)
                y[i] ~ Normal(phi[i], s[i])
            end
        end
        b_def = @bugs begin
            for i in 1:12
                phi[i] ~ Normal(0, 1)
                z[i] = phi[i] * w[i]
            end
            x ~ Normal(sum(z[1:12]), 1)
        end
        j_def = @bugs begin
            for i in 1:12
                phi[i] ~ Normal(0, 1)
                y[i] ~ Normal(phi[i], s[i])
                z[i] = phi[i] * w[i]
            end
            x ~ Normal(sum(z[1:12]), 1)
        end
        s = collect(range(0.5, 2.0; length=12))
        w = collect(1.0:12.0)
        yv = randn(rng, 12)
        a = a_def((; y=yv, s))
        b = b_def((; x=0.7, w))
        j = j_def((; y=yv, s, w, x=0.7))
        explicit = [@varname(phi[i]) for i in 1:12]
        m_name = meld([a, b], [:phi, :phi]; pooling=Dictatorial(2))
        m_mixed = meld([a, b], [:phi, explicit]; pooling=Dictatorial(2))
        @test m_name.links[1].nodes == explicit
        @test m_name.links[2].nodes == explicit
        for _ in 1:3
            nt = (; phi=randn(rng, 12))
            lp_joint = LogDensityProblems.logdensity(j, params_at(j, nt))
            @test LogDensityProblems.logdensity(m_name, params_at(m_name, nt)) ≈ lp_joint atol =
                1e-9
            @test LogDensityProblems.logdensity(m_mixed, params_at(m_mixed, nt)) ≈ lp_joint atol =
                1e-9
        end
    end

    @testset "a supplied marginal takes precedence over fixing" begin
        a_def = @bugs begin
            phi ~ Normal(0, 1)
            y ~ Normal(phi, 1)
        end
        a = a_def((; y=0.8))
        b = a_def((; y=-0.8))
        plain = meld([a, b], [:phi, :phi]; pooling=Dictatorial(1))
        @test plain.roles == [:carrier, :fixed]
        @test plain.marginals[2] === nothing
        supplied = meld(
            [a, b], [:phi, :phi]; pooling=Dictatorial(1), marginals=Dict(2 => Normal(5, 5))
        )
        @test supplied.roles == [:carrier, :conditioned]
        @test supplied.exponents == [0.0, -1.0]
        for φ in (-0.5, 1.5)
            @test LogDensityProblems.logdensity(supplied, [φ]) ≈
                LogDensityProblems.logdensity(plain, [φ]) + logpdf(Normal(0, 1), φ) -
                  logpdf(Normal(5, 5), φ)
        end
        @test nsubmodels(plain) == 2
    end

    @testset "argument errors" begin
        a_def = @bugs begin
            phi ~ Normal(0, 1)
            y ~ Normal(phi, 1)
        end
        a = a_def((; y=0.8))
        b = a_def((; y=-0.8))
        @test_throws ArgumentError meld([a, b], [:phi])
        @test_throws ArgumentError meld([a, b], [:phi, :nope])
        @test_throws ArgumentError meld([a, b], [:phi, :y])      # observed
        @test_throws ArgumentError meld([a, b], [:phi, :phi]; pooling=Dictatorial(3))
        @test_throws ArgumentError meld(
            [a, b], [:phi, :phi]; pooling=LogarithmicPooling([1.0])
        )
        @test_throws ArgumentError meld([a, b], [:phi, :phi]; marginals=Dict(5 => Normal()))
        @test_throws ArgumentError meld(JuliaBUGS.BUGSModel[], [])
        # Two submodels that both define the link deterministically.
        l_def = @bugs begin
            theta ~ Normal(0, 1)
            phi = exp(theta)
            y ~ Normal(phi, 1)
        end
        l1 = l_def((; y=0.1))
        l2 = l_def((; y=0.2))
        @test_throws ArgumentError meld([l1, l2], [:phi, :phi])
        # A logical link that depends on a stochastic generated quantity.
        bad_def = @bugs begin
            theta ~ Normal(0, 1)
            xi ~ Normal(0, 1)
            phi = exp(theta + xi)
            y ~ Normal(theta, 1)
        end
        bad = bad_def((; y=0.1))
        @test_throws ArgumentError meld([bad, a], [:phi, :phi]; pooling=Dictatorial(1))
        mm = meld([a, b], [:phi, :phi])
        @test_throws DimensionMismatch LogDensityProblems.logdensity(mm, [0.0, 1.0])
        @test sprint(show, mm) isa String
    end
end
