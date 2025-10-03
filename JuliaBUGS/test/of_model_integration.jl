using JuliaBUGS
using JuliaBUGS: @model, @of, unflatten
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

        @model function dynamic_regression((; coeffs, sigma, y), X, n)
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
        DynamicParams3 = of(DynamicParams; n=3)
        params = unflatten(DynamicParams3, missing)
        model = dynamic_regression(params, X, 3)
        @test model isa JuliaBUGS.BUGSModel

        # Test with type annotation using concrete type
        @model function typed_dynamic_regression((; coeffs, sigma, y)::DynamicParams3, X, n)
            sigma ~ dgamma(0.001, 0.001)
            for i in 1:n
                coeffs[i] ~ dnorm(0, 0.001)
            end
            for i in 1:100
                y[i] ~ dnorm(coeffs[1] * X[i, 1], sigma)
            end
        end

        typed_model = typed_dynamic_regression(params, X, 3)
        @test typed_model isa JuliaBUGS.BUGSModel
    end

    @testset "Bounded parameters" begin
        @model function bounded_model((;
            alpha,      # Bounded between -10 and 10
            beta,     # Positive only
            gamma,    # Negative only
            p,             # Probability
            y,              # Observations
        ), n)
            alpha ~ dunif(-10, 10)
            beta ~ dgamma(1, 1)
            gamma ~ dnorm(-5, 1)  # Prior centered at -5
            p ~ dbeta(2, 2)

            # Simplified likelihood
            for i in 1:n
                y[i] ~ dnorm(alpha, 1 / p)
            end
        end

        model = bounded_model((; y=zero(of(Array, 100))), 100)
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
            (; mu_global, tau_global, group_means, group_taus, y), n_groups, n_obs_per_group
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

        HierarchicalParams5_20 = of(HierarchicalParams; n_groups=5, n_obs_per_group=20)
        model = hierarchical(unflatten(HierarchicalParams5_20, missing), 5, 20)
        @test model isa JuliaBUGS.BUGSModel

        # Test with type annotation using concrete type
        @model function typed_hierarchical(
            (; mu_global, tau_global, group_means, group_taus, y)::HierarchicalParams5_20,
            n_groups,
            n_obs_per_group,
        )
            mu_global ~ dnorm(0, 0.001)
            tau_global ~ dgamma(0.001, 0.001)
            for g in 1:n_groups
                group_means[g] ~ dnorm(mu_global, tau_global)
                group_taus[g] ~ dgamma(0.001, 0.001)
                for i in 1:n_obs_per_group
                    y[g, i] ~ dnorm(group_means[g], group_taus[g])
                end
            end
        end

        typed_model = typed_hierarchical(unflatten(HierarchicalParams5_20, missing), 5, 20)
        @test typed_model isa JuliaBUGS.BUGSModel
    end

    @testset "Mixed type annotations" begin
        # Test mixing different element types
        MixedParams = @of(
            int_array = of(Array, Int, 10),
            float_array = of(Array, Float64, 10),
            bool_array = of(Array, Bool, 10)
        )

        @model function mixed_types((; int_array, float_array, bool_array)::MixedParams, n)
            for i in 1:n
                int_array[i] ~ dpois(5.0)
                float_array[i] ~ dnorm(0, 1)
                bool_array[i] ~ dbern(0.5)
            end
        end

        model = mixed_types((;), 10)
        @test model isa JuliaBUGS.BUGSModel
    end
end
