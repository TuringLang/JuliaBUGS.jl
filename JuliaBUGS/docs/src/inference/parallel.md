# Parallel and Distributed Sampling

`AbstractMCMC` and `AdvancedHMC` support both parallel and distributed sampling.

## Parallel Sampling (Multi-threaded)

To perform multi-threaded sampling of multiple chains, start Julia with the `-t <n_threads>` argument.

```julia
n_chains = 4
samples_and_stats = AbstractMCMC.sample(
    model,
    AdvancedHMC.NUTS(0.65),
    AbstractMCMC.MCMCThreads(),
    n_samples,
    n_chains;
    chain_type = Chains,
    n_adapts = n_adapts,
    init_params = [initial_θ for _ = 1:n_chains],
    discard_initial = n_adapts,
)
```

The key differences from single-chain sampling:
- `AbstractMCMC.MCMCThreads()`: enables multi-threaded sampling
- `n_chains`: number of chains to sample in parallel
- `init_params`: vector of initial parameters (one per chain)

## Distributed Sampling (Multi-process)

To perform distributed sampling, start Julia with the `-p <n_processes>` argument.

Ensure all functions and modules are available on all processes using `@everywhere`:

```julia
@everywhere begin
    using JuliaBUGS, LogDensityProblems, AbstractMCMC, AdvancedHMC, MCMCChains, ADTypes, ReverseDiff

    # Define any custom functions here
    # Use `@bugs_primitive` to register functions for use in the model
end

n_chains = nprocs() - 1  # use all worker processes
samples_and_stats = AbstractMCMC.sample(
    model,
    AdvancedHMC.NUTS(0.65),
    AbstractMCMC.MCMCDistributed(),
    n_samples,
    n_chains;
    chain_type = Chains,
    n_adapts = n_adapts,
    init_params = [initial_θ for _ = 1:n_chains],
    discard_initial = n_adapts,
    progress = false,  # progress logging can cause issues in distributed mode
)
```

The key differences:
- `AbstractMCMC.MCMCDistributed()`: enables distributed sampling
- `progress = false`: recommended to avoid TTY issues in distributed settings
