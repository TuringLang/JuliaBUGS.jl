# R Interface

[**RJuliaBUGS**](https://mateusmaiads.github.io/rjuliabugs/) lets you run BUGS models from R using Julia's fast sampling algorithms.

Created by [Mateus Maia](https://github.com/MateusMaiaDS) as part of Google Summer of Code 2025.

## What is RJuliaBUGS?

RJuliaBUGS connects R to JuliaBUGS. You write models in BUGS syntax and run them from R, but they execute using Julia's modern samplers like Hamiltonian Monte Carlo (HMC).

**Key benefits:**
- Keep your existing BUGS models
- Run models faster with Julia's algorithms
- Stay in R for all analysis
- Works with `bayesplot`, `posterior`, `coda`, and other R packages

## Related Julia Packages

For R users working with Julia:

- [`RCall.jl`](https://github.com/JuliaInterop/RCall.jl) - Run R from Julia
- [`RData.jl`](https://github.com/JuliaData/RData.jl) - Read/write R data files
- [`DataFrames.jl`](https://github.com/JuliaData/DataFrames.jl) - Data manipulation (like `dplyr`)
- [`CSV.jl`](https://github.com/JuliaData/CSV.jl) - Work with CSV files
- [`JSON.jl`](https://github.com/JuliaIO/JSON.jl), [`JSON3.jl`](https://github.com/quinnj/JSON3.jl) - Work with JSON data
