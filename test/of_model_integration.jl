using JuliaBUGS
using JuliaBUGS: @model, @of
using Test

@testset "of type integration with @model" begin
    @testset "Variable dimension models" begin
        # Model with symbolic dimensions
        DynamicParams = @of(
            n = of(Int; constant=true),
            coeffs = of(Array, n),
            sigma = of(Real, 0, nothing),
            y = of(Array, 100)
        )

        @model function dynamic_regression((coeffs, sigma, y)::DynamicParams, X, n)
            sigma ~ dgamma(0.001, 0.001)
            for i in 1:n
                coeffs[i] ~ dnorm(0, 0.001)
            end

            # Simple model - just use first coefficient for simplicity
            for i in 1:100
                y[i] ~ dnorm(coeffs[1] * X[i, 1], sigma)
            end
        end

        # Create model with n=3
        X = randn(100, 3)
        model = dynamic_regression((n=3,), X, 3)
        @test model isa JuliaBUGS.BUGSModel
    end

    @testset "Bounded parameters" begin
        @model function bounded_model(
            (;
                alpha::of(Real, -10, 10),      # Bounded between -10 and 10
                beta::of(Real, 0, nothing),     # Positive only
                gamma::of(Real, nothing, 0),    # Negative only
                p::of(Real, 0, 1),             # Probability
                y::of(Array, 100),              # Observations
            ),
            n,
        )
            alpha ~ dunif(-10, 10)
            beta ~ dgamma(1, 1)
            gamma ~ dnorm(-5, 1)  # Prior centered at -5
            p ~ dbeta(2, 2)

            # Simplified likelihood
            for i in 1:n
                y[i] ~ dnorm(alpha, 1 / p)
            end
        end

        model = bounded_model((), 100)
        @test model isa JuliaBUGS.BUGSModel
    end

    @testset "Nested structures" begin
        # Hierarchical model with nested structure
        HierarchicalParams = @of(
            n_groups = of(Int; constant=true),
            n_obs_per_group = of(Int; constant=true),

            # Global parameters
            mu_global = of(Real),
            tau_global = of(Real, 0, nothing),

            # Group-level parameters
            group_means = of(Array, n_groups),
            group_taus = of(Array, n_groups),

            # Observations
            y = of(Array, n_groups, n_obs_per_group)
        )

        @model function hierarchical(
            (mu_global, tau_global, group_means, group_taus, y)::HierarchicalParams,
            n_groups,
            n_obs_per_group,
        )
            # Global priors
            mu_global ~ dnorm(0, 0.001)
            tau_global ~ dgamma(0.001, 0.001)

            # Group-level priors and likelihood
            for g in 1:n_groups
                group_means[g] ~ dnorm(mu_global, tau_global)
                group_taus[g] ~ dgamma(0.001, 0.001)

                for i in 1:n_obs_per_group
                    y[g, i] ~ dnorm(group_means[g], group_taus[g])
                end
            end
        end

        model = hierarchical((n_groups=5, n_obs_per_group=20), 5, 20)
        @test model isa JuliaBUGS.BUGSModel
    end

    @testset "Mixed type annotations" begin
        # Test mixing different element types
        MixedParams = @of(
            int_array = of(Array, Int, 10),
            float_array = of(Array, Float64, 10),
            bool_array = of(Array, Bool, 10)
        )

        @model function mixed_types((int_array, float_array, bool_array)::MixedParams, n)
            for i in 1:n
                int_array[i] ~ dpois(5.0)
                float_array[i] ~ dnorm(0, 1)
                bool_array[i] ~ dbern(0.5)
            end
        end

        model = mixed_types(NamedTuple(), 10)
        @test model isa JuliaBUGS.BUGSModel
    end
end