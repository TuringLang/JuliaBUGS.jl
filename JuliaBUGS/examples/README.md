# JuliaBUGS Examples

We have adapted some examples to show how to use JuliaBUGS in this repository.

Run an example with its project environment, for example:

```sh
julia --project=examples examples/gp.jl
```

These examples use Mooncake-backed gradient sampling. The SIR example also loads
SciMLSensitivity because reverse-mode AD through an ODE solve requires SciML's
sensitivity rules.

## Sources

* SIR: https://github.com/TuringLang/Turing-Workshop/tree/main/2023-MRC-BSU-and-UKHSA/Part-2-More-Julia-and-some-Bayesian-inference
* GP: https://turinglang.org/docs/tutorials/gaussian-processes-introduction/
* BNN: https://turinglang.org/docs/tutorials/bayesian-neural-networks/
