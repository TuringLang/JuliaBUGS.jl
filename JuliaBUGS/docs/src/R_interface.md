# R Interface

As part of the Google Summer of Code (GSoC) 2025, a project was completed under the [Turing.jl](https://turinglang.org/) organization to develop an R interface for [`JuliaBUGS.jl`](https://github.com/TuringLang/JuliaBUGS.jl). The outcome of this project was the creation of the `rjuliabugs` package, developed by Mateus Maia with mentorship from Xianda Sun and Robert Goudie.  

`rjuliabugs` provides a bridge between `R` and `JuliaBUGS`, the BUGS-style Bayesian modeling interface developed in Julia. JuliaBUGS enables users to specify models in the familiar BUGS syntax while leveraging the speed and flexibility of Julia, including advanced inference engines such as Hamiltonian Monte Carlo (HMC) through Turing.jl. With `rjuliabugs`, R users can run BUGS models directly from R, benefiting from Julia’s efficient inference algorithms without leaving the R environment.  

The package integrates seamlessly with R’s post-processing ecosystem, including tools like `bayesplot`, `posterior`, and `coda`, making diagnostics and visualization immediately accessible to applied researchers. This lowers the barrier for BUGS users to adopt modern Bayesian tools while retaining their existing model codebase.  


Additional packages to provide an integration from Julia to language:

- [`RCall.jl`](https://github.com/JuliaInterop/RCall.jl): interaction with R runtime.
- [`RData.jl`](https://github.com/JuliaData/RData.jl): reading and writing R data files.
- [`DataFrames.jl`](https://github.com/JuliaData/DataFrames.jl): `pandas` and `dplyr` for Julia.
- [`CSV.jl`](https://github.com/JuliaData/CSV.jl): CSV file reading and writing.
- [`JSON.jl`](https://github.com/JuliaIO/JSON.jl), [`JSON3.jl`](https://github.com/quinnj/JSON3.jl), - [`Serde.jl`](https://github.com/bhftbootcamp/Serde.jl): JSON file reading and writing.
