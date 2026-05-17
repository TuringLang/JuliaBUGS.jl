# Functions

Most of the [functions from BUGS](https://www.multibugs.org/documentation/latest/Functions.html) have been implemented. `JuliaBUGS` directly utilizes functions from the Julia Standard Library when they share the same names and functionalities. For functions not available in the Julia Standard Library and other popular libraries, we have developed equivalents within `JuliaBUGS.BUGSPrimitives`.

!!! warning "No keyword arguments syntax in BUGS"
    Some of the listed functions accept additional or keyword arguments (e.g. `trunc`, `sum`, `sort`, `mean`). `JuliaBUGS` currently only supports positional arguments of type `Real` or `AbstractArray{<:Real}`, and does not accept keyword-argument syntax. Default values of any optional or keyword arguments are used automatically.

## From the Julia Standard Library

The following are re-used directly from Julia's `Base` / `Base.Math` (linked to the upstream Julia documentation):

| Function | Description |
|---|---|
| [`abs`](https://docs.julialang.org/en/v1/base/math/#Base.abs) | Absolute value |
| [`exp`](https://docs.julialang.org/en/v1/base/math/#Base.exp-Tuple{Float64}) | Exponential |
| [`log`](https://docs.julialang.org/en/v1/base/math/#Base.log-Tuple{Number}) | Natural logarithm |
| [`sqrt`](https://docs.julialang.org/en/v1/base/math/#Base.sqrt-Tuple{Number}) | Square root |
| [`trunc`](https://docs.julialang.org/en/v1/base/math/#Base.trunc) | Truncate toward zero |
| [`min`](https://docs.julialang.org/en/v1/base/math/#Base.min) | Minimum of two scalars |
| [`max`](https://docs.julialang.org/en/v1/base/math/#Base.max) | Maximum of two scalars |
| [`sum`](https://docs.julialang.org/en/v1/base/collections/#Base.sum) | Sum over an array |
| [`sort`](https://docs.julialang.org/en/v1/base/sort/#Base.sort) | Sort an array |
| [`sin`](https://docs.julialang.org/en/v1/base/math/#Base.sin-Tuple{Number}), [`cos`](https://docs.julialang.org/en/v1/base/math/#Base.cos-Tuple{Number}), [`tan`](https://docs.julialang.org/en/v1/base/math/#Base.tan-Tuple{Number}) | Trigonometric functions |
| [`asin`](https://docs.julialang.org/en/v1/base/math/#Base.asin-Tuple{Number}), [`acos`](https://docs.julialang.org/en/v1/base/math/#Base.acos-Tuple{Number}), [`atan`](https://docs.julialang.org/en/v1/base/math/#Base.atan-Tuple{Number}) | Inverse trig |
| [`asinh`](https://docs.julialang.org/en/v1/base/math/#Base.asinh-Tuple{Number}), [`acosh`](https://docs.julialang.org/en/v1/base/math/#Base.acosh-Tuple{Number}), [`atanh`](https://docs.julialang.org/en/v1/base/math/#Base.atanh-Tuple{Number}) | Inverse hyperbolic |
| `mean` | Available via `JuliaBUGS.BUGSPrimitives.mean(x::AbstractArray)` |

## From [LogExpFunctions](https://github.com/JuliaStats/LogExpFunctions.jl)

| Function | Description |
|---|---|
| [`cloglog`](https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.cloglog) | Complementary log-log: `log(-log(1 - x))` |
| [`cexpexp`](https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.cexpexp) | Inverse of `cloglog`: `1 - exp(-exp(x))` |
| [`logit`](https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.logit) | Logit: `log(x / (1 - x))` |
| [`logistic`](https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.logistic) | Logistic (sigmoid): `1 / (1 + exp(-x))` |

## From `JuliaBUGS.BUGSPrimitives`

```@docs
JuliaBUGS.BUGSPrimitives.equals
JuliaBUGS.BUGSPrimitives.inprod
JuliaBUGS.BUGSPrimitives.inverse
JuliaBUGS.BUGSPrimitives.logdet
JuliaBUGS.BUGSPrimitives.logfact
JuliaBUGS.BUGSPrimitives.loggam
JuliaBUGS.BUGSPrimitives.icloglog
JuliaBUGS.BUGSPrimitives.ilogit
JuliaBUGS.BUGSPrimitives.mexp
JuliaBUGS.BUGSPrimitives.phi
JuliaBUGS.BUGSPrimitives.probit
JuliaBUGS.BUGSPrimitives.pow
JuliaBUGS.BUGSPrimitives.rank
JuliaBUGS.BUGSPrimitives.ranked
JuliaBUGS.BUGSPrimitives.sd
JuliaBUGS.BUGSPrimitives.softplus
JuliaBUGS.BUGSPrimitives._step
JuliaBUGS.BUGSPrimitives.arcsin
JuliaBUGS.BUGSPrimitives.arcsinh
JuliaBUGS.BUGSPrimitives.arccos
JuliaBUGS.BUGSPrimitives.arccosh
JuliaBUGS.BUGSPrimitives.arctan
JuliaBUGS.BUGSPrimitives.arctanh
```
