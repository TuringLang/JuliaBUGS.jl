using JuliaBUGS: Gibbs
using JuliaBUGS.BUGSPrimitives: cut
using JuliaBUGS.Model:
    model_parameters,
    variable_type,
    set_evaluation_mode,
    FixedParameter,
    GeneratedQuantity,
    ModelParameter,
    Observation,
    UseGeneratedLogDensityFunction,
    UseGraph

@testset "NestedCut" begin
    Z_obs = 1.0
    Y_obs = 3.0

    model_def = @bugs begin
        phi ~ dnorm(0, 1)
        Z ~ dnorm(phi, 1)
        phi_cut = cut(phi)
        theta ~ dnorm(0, 1)
        Y ~ dnorm(phi_cut + theta, 1)
    end

    # Cut marginals (closed form, see testset "Sampling"):
    #   phi | Z ~ N(Z/2, 1/2); theta | phi, Y ~ N((Y - phi)/2, 1/2)
    cut_phi_mean = Z_obs / 2
    cut_phi_var = 0.5
    cut_theta_mean = (Y_obs - cut_phi_mean) / 2
    cut_theta_var = 0.5 + cut_phi_var / 4

    # Full posterior mean of (phi, theta): solve P m = b with
    # P = [3 1; 1 2], b = [Z + Y, Y]
    full_means = [3.0 1.0; 1.0 2.0] \ [Z_obs + Y_obs, Y_obs]
    @test abs(full_means[1] - cut_phi_mean) > 0.1

    @testset "cut_upstream_model" begin
        model = compile(model_def, (; Z=Z_obs, Y=Y_obs))
        upstream = cut_upstream_model(model)

        @test model_parameters(upstream) == [@varname(phi)]
        @test variable_type(upstream, @varname(Z)) == Observation
        @test variable_type(upstream, @varname(Y)) == GeneratedQuantity
        @test variable_type(upstream, @varname(theta)) == GeneratedQuantity
        @test variable_type(upstream, @varname(phi_cut)) == GeneratedQuantity
        @test variable_type(upstream, @varname(phi)) == ModelParameter

        upstream_gen = set_evaluation_mode(upstream, UseGeneratedLogDensityFunction())
        upstream_untrans = JuliaBUGS.settrans(upstream, false)
        for phi_val in (0.0, 0.7, -1.3)
            env = JuliaBUGS.BangBang.setindex!!(
                upstream.evaluation_env, phi_val, @varname(phi)
            )
            m_graph = JuliaBUGS.BangBang.setproperty!!(
                upstream_untrans, :evaluation_env, env
            )
            _, lp_graph = AbstractPPL.evaluate!!(m_graph; transformed=false)

            m_gen = JuliaBUGS.BangBang.setproperty!!(upstream_gen, :evaluation_env, env)
            _, lp_gen = AbstractPPL.evaluate!!(m_gen; transformed=true)

            # Normal priors have identity bijectors, so the transformed density is the same.
            expected = logpdf(Normal(0, 1), phi_val) + logpdf(Normal(phi_val, 1), Z_obs)
            @test lp_graph ≈ expected
            @test lp_gen ≈ expected
        end
    end

    @testset "cut_downstream_model" begin
        model = compile(model_def, (; Z=Z_obs, Y=Y_obs), (; phi=0.4, theta=0.9))
        downstream = cut_downstream_model(model)

        @test model_parameters(downstream) == [@varname(theta)]
        @test variable_type(downstream, @varname(phi)) == FixedParameter
        @test variable_type(downstream, @varname(theta)) == ModelParameter
        @test variable_type(downstream, @varname(Y)) == Observation
        @test variable_type(downstream, @varname(Z)) == Observation

        phi_val = downstream.evaluation_env.phi
        theta_val = downstream.evaluation_env.theta
        m_untrans = JuliaBUGS.settrans(downstream, false)
        _, lp_graph = AbstractPPL.evaluate!!(m_untrans; transformed=false)
        downstream_gen = set_evaluation_mode(downstream, UseGeneratedLogDensityFunction())
        _, lp_gen = AbstractPPL.evaluate!!(downstream_gen; transformed=true)

        expected =
            logpdf(Normal(0, 1), theta_val) +
            logpdf(Normal(phi_val + theta_val, 1), Y_obs) +
            logpdf(Normal(phi_val, 1), Z_obs)  # constant term
        @test lp_graph ≈ expected
        @test lp_gen ≈ expected
    end

    @testset "@model front end" begin
        #! format: off
        @model function cut_model_maker((; phi, theta, Z, Y))
            phi ~ Normal(0, 1)
            Z ~ Normal(phi, 1)
            phi_cut = cut(phi)
            theta ~ Normal(0, 1)
            Y ~ Normal(phi_cut + theta, 1)
        end
        #! format: on
        model = cut_model_maker((; Z=Z_obs, Y=Y_obs))
        upstream = cut_upstream_model(model)
        @test model_parameters(upstream) == [@varname(phi)]
        @test model_parameters(cut_downstream_model(model)) == [@varname(theta)]
    end

    @testset "Sampling" begin
        using AdvancedMH: RWMH
        using MCMCChains: Chains
        using StableRNGs: StableRNG
        using Statistics

        model = compile(model_def, (; Z=Z_obs, Y=Y_obs))

        sampler = NestedCut(RWMH([Normal(0, 0.7)]), RWMH([Normal(0, 0.7)]); inner_steps=5)
        chain = Base.invokelatest(
            sample,
            StableRNG(1),
            model,
            sampler,
            20_000;
            progress=false,
            chain_type=Chains,
            discard_initial=2_000,
        )
        @test mean(chain[:phi]) ≈ cut_phi_mean atol = 0.05
        @test var(chain[:phi]) ≈ cut_phi_var atol = 0.1
        @test mean(chain[:theta]) ≈ cut_theta_mean atol = 0.05
        @test var(chain[:theta]) ≈ cut_theta_var atol = 0.1

        @testset "warm_start=false" begin
            sampler_cold = NestedCut(
                RWMH([Normal(0, 0.7)]),
                RWMH([Normal(0, 0.7)]);
                inner_steps=30,
                warm_start=false,
            )
            chain_cold = Base.invokelatest(
                sample,
                StableRNG(2),
                model,
                sampler_cold,
                4_000;
                progress=false,
                chain_type=Chains,
                discard_initial=1_000,
            )
            @test mean(chain_cold[:phi]) ≈ cut_phi_mean atol = 0.1
            @test mean(chain_cold[:theta]) ≈ cut_theta_mean atol = 0.15
        end

        @testset "gradient stage samplers" begin
            using AdvancedHMC: NUTS
            using ADTypes: AutoForwardDiff
            sampler_nuts = NestedCut(
                (NUTS(0.65), AutoForwardDiff()),
                (NUTS(0.65), AutoForwardDiff());
                inner_steps=3,
            )
            chain_nuts = Base.invokelatest(
                sample,
                StableRNG(3),
                model,
                sampler_nuts,
                3_000;
                progress=false,
                chain_type=Chains,
                discard_initial=500,
            )
            @test mean(chain_nuts[:phi]) ≈ cut_phi_mean atol = 0.1
            @test mean(chain_nuts[:theta]) ≈ cut_theta_mean atol = 0.1
        end

        @testset "Gibbs as stage sampler" begin
            sampler_gibbs = NestedCut(
                Gibbs(cut_upstream_model(model), RWMH(1)),
                Gibbs(cut_downstream_model(model), RWMH(1));
                inner_steps=5,
            )
            chain_gibbs = Base.invokelatest(
                sample,
                StableRNG(4),
                model,
                sampler_gibbs,
                20_000;
                progress=false,
                chain_type=Chains,
                discard_initial=2_000,
            )
            @test mean(chain_gibbs[:phi]) ≈ cut_phi_mean atol = 0.05
            @test mean(chain_gibbs[:theta]) ≈ cut_theta_mean atol = 0.05
        end
    end

    @testset "Errors" begin
        using AdvancedMH: RWMH
        using StableRNGs: StableRNG

        no_cut_def = @bugs begin
            phi ~ dnorm(0, 1)
            Z ~ dnorm(phi, 1)
        end
        no_cut_model = compile(no_cut_def, (; Z=Z_obs))
        sampler = NestedCut(RWMH([Normal(0, 0.7)]), RWMH([Normal(0, 0.7)]))
        @test_throws ArgumentError cut_upstream_model(no_cut_model)

        nonseparating_def = @bugs begin
            mu ~ dnorm(0, 1)
            phi ~ dnorm(mu, 1)
            Z ~ dnorm(phi, 1)
            phi_cut = cut(phi)
            theta ~ dnorm(mu, 1)
            Y ~ dnorm(phi_cut + theta, 1)
        end
        nonseparating_model = compile(nonseparating_def, (; Z=Z_obs, Y=Y_obs))
        @test_throws ArgumentError cut_upstream_model(nonseparating_model)

        @test_throws ArgumentError NestedCut(
            RWMH([Normal(0, 0.7)]), RWMH([Normal(0, 0.7)]); inner_steps=0
        )
    end
end
