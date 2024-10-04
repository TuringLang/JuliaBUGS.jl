# Benchmarking Nimble's Performance in Computing Log-Density and Gradient

This benchmark evaluates the performance of Nimble in computing the log-density and its gradient for various models. To compute gradients in Nimble, it is necessary to use the compiled model.

The current code utilizes the [BUGS models provided by Nimble](https://github.com/nimble-dev/nimble/tree/devel/packages/nimble/inst/classic-bugs). The repository also contains some scripts to run the models in JAGS. Some models are modified from the original ones in MultiBUGS to fit the interface of Nimble. It's worth noting that these examples are quite old now, and some of them may need to be updated to work with the current versions of Nimble.

Additionally, there is some relevant [code](https://github.com/nimble-dev/nimble/blob/devel/packages/AD-full-tests/test-ADmodels-full.R#L1143) from Nimble's ADTest that could provide useful insights when conducting a more thorough benchmarking exercise.

## Caveats in Comparing Nimble with Stan

It's important to keep in mind that, similar to the caveats in comparing JuliaBUGS and Stan, the Stan models are generally more optimized through the use of vectorized operations. As a result, the speed should not be directly compared between Nimble and Stan. Instead, the results should be viewed as an indication of the relative performance scale between the two frameworks.

## Running the benchmark

To run the benchmark:

1. Ensure you have Julia installed. The required package information is included in `Project.toml`.

2. Install R and the following R packages:
   - `nimble`
   - `microbenchmark`

3. Running the benchmarking code in Julia REPL.

Note: This benchmark is intended for use by JuliaBUGS developers. Additional setup may be required.
