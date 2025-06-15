@testset "Parallel and Distributed Sampling" begin
    # Use a simple model for testing
    model_def = @bugs begin
        mu ~ dnorm(0, 0.0001)
        tau ~ dgamma(0.01, 0.01)
        sigma = 1 / sqrt(tau)
        for i in 1:N
            x[i] ~ dnorm(mu, tau)
        end
    end

    # Generate synthetic data
    N = 10
    true_mu = 5.0
    true_sigma = 2.0
    rng = StableRNG(42)
    x_data = true_mu .+ true_sigma .* randn(rng, N)

    data = (N=N, x=x_data)
    inits = (mu=0.0, tau=1.0)

    model = compile(model_def, data, inits)
    # Use compile=Val(false) for thread safety with ReverseDiff
    ad_model = ADgradient(:ReverseDiff, model; compile=Val(false))

    # Single chain reference
    n_samples = 1000
    reference_chain = sample(
        StableRNG(123),
        ad_model,
        NUTS(0.8),
        n_samples;
        progress=false,
        n_adapts=500,
        discard_initial=500,
    )

    @testset "MCMCThreads" begin
        n_chains = 4

        # Test basic functionality
        chains = sample(
            StableRNG(123),
            ad_model,
            NUTS(0.8),
            MCMCThreads(),
            n_samples,
            n_chains;
            progress=false,
            n_adapts=500,
            discard_initial=500,
        )

        @test chains isa AbstractVector
        @test length(chains) == n_chains
        @test all(length(chain) == n_samples for chain in chains)

        # Test reproducibility with same seed
        chains2 = sample(
            StableRNG(123),
            ad_model,
            NUTS(0.8),
            MCMCThreads(),
            n_samples,
            n_chains;
            progress=false,
            n_adapts=500,
            discard_initial=500,
        )

        # Check that results are identical with same seed
        for i in 1:n_chains
            @test all(chains[i][j] == chains2[i][j] for j in 1:n_samples)
        end

        # Test different seeds produce different results
        chains3 = sample(
            StableRNG(456),
            ad_model,
            NUTS(0.8),
            MCMCThreads(),
            n_samples,
            n_chains;
            progress=false,
            n_adapts=500,
            discard_initial=500,
        )

        # Results should be different with different seeds
        @test !all(chains[1][1] == chains3[1][1])
    end

    @testset "MCMCDistributed" begin
        # Only run if Distributed is available
        try
            using Distributed

            # Add workers if needed
            if nworkers() < 2
                addprocs(2)
            end

            @everywhere begin
                using JuliaBUGS
                using AbstractMCMC
                using AdvancedHMC
                using LogDensityProblems
                using LogDensityProblemsAD
                using ADTypes
                using StableRNGs
            end

            n_chains = 2

            # Test basic functionality
            chains = sample(
                StableRNG(123),
                ad_model,
                NUTS(0.8),
                MCMCDistributed(),
                n_samples,
                n_chains;
                progress=false,
                n_adapts=500,
                discard_initial=500,
            )

            @test chains isa AbstractVector
            @test length(chains) == n_chains
            @test all(length(chain) == n_samples for chain in chains)

            # Clean up workers
            rmprocs(workers())
        catch e
            if e isa ArgumentError && occursin("Distributed", string(e))
                @info "Skipping MCMCDistributed tests - Distributed not available"
            else
                rethrow(e)
            end
        end
    end

    @testset "Chain statistics" begin
        # Test that parallel chains produce reasonable statistics
        n_chains = 4
        chains = sample(
            StableRNG(123),
            ad_model,
            NUTS(0.8),
            MCMCThreads(),
            n_samples,
            n_chains;
            progress=false,
            n_adapts=500,
            discard_initial=500,
            chain_type=Chains,
        )

        # Extract mu parameter
        mu_chains = chains[:mu]

        # Check convergence
        @test mean(mu_chains) ≈ true_mu atol = 0.5
        @test std(mu_chains) < 1.0

        # Check R-hat (if available)
        if hasproperty(chains, :rhat)
            @test all(chains.rhat .< 1.1)
        end
    end
end
