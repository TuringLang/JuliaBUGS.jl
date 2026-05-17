
# Functions {#Functions}

Most of the [functions from BUGS](https://www.multibugs.org/documentation/latest/Functions.html) have been implemented. `JuliaBUGS` directly utilizes functions from the Julia Standard Library when they share the same names and functionalities. For functions not available in the Julia Standard Library and other popular libraries, we have developed equivalents within `JuliaBUGS.BUGSPrimitives`.

::: warning No keyword arguments syntax in BUGS

Some of the listed functions accept additional or keyword arguments (e.g. `trunc`, `sum`, `sort`, `mean`). `JuliaBUGS` currently only supports positional arguments of type `Real` or `AbstractArray{<:Real}`, and does not accept keyword-argument syntax. Default values of any optional or keyword arguments are used automatically.

:::

## From the Julia Standard Library {#From-the-Julia-Standard-Library}

The following are re-used directly from Julia&#39;s `Base` / `Base.Math` (linked to the upstream Julia documentation):

|                                                                                                                                                                                                                                          Function |                                                     Description |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------:| ---------------------------------------------------------------:|
|                                                                                                                                                                                     [`abs`](https://docs.julialang.org/en/v1/base/math/#Base.abs) |                                                  Absolute value |
|                                                                                                                                                                      [`exp`](https://docs.julialang.org/en/v1/base/math/#Base.exp-Tuple{Float64}) |                                                     Exponential |
|                                                                                                                                                                       [`log`](https://docs.julialang.org/en/v1/base/math/#Base.log-Tuple{Number}) |                                               Natural logarithm |
|                                                                                                                                                                     [`sqrt`](https://docs.julialang.org/en/v1/base/math/#Base.sqrt-Tuple{Number}) |                                                     Square root |
|                                                                                                                                                                                 [`trunc`](https://docs.julialang.org/en/v1/base/math/#Base.trunc) |                                            Truncate toward zero |
|                                                                                                                                                                                     [`min`](https://docs.julialang.org/en/v1/base/math/#Base.min) |                                          Minimum of two scalars |
|                                                                                                                                                                                     [`max`](https://docs.julialang.org/en/v1/base/math/#Base.max) |                                          Maximum of two scalars |
|                                                                                                                                                                              [`sum`](https://docs.julialang.org/en/v1/base/collections/#Base.sum) |                                               Sum over an array |
|                                                                                                                                                                                   [`sort`](https://docs.julialang.org/en/v1/base/sort/#Base.sort) |                                                   Sort an array |
|             [`sin`](https://docs.julialang.org/en/v1/base/math/#Base.sin-Tuple{Number}), [`cos`](https://docs.julialang.org/en/v1/base/math/#Base.cos-Tuple{Number}), [`tan`](https://docs.julialang.org/en/v1/base/math/#Base.tan-Tuple{Number}) |                                         Trigonometric functions |
|       [`asin`](https://docs.julialang.org/en/v1/base/math/#Base.asin-Tuple{Number}), [`acos`](https://docs.julialang.org/en/v1/base/math/#Base.acos-Tuple{Number}), [`atan`](https://docs.julialang.org/en/v1/base/math/#Base.atan-Tuple{Number}) |                                                    Inverse trig |
| [`asinh`](https://docs.julialang.org/en/v1/base/math/#Base.asinh-Tuple{Number}), [`acosh`](https://docs.julialang.org/en/v1/base/math/#Base.acosh-Tuple{Number}), [`atanh`](https://docs.julialang.org/en/v1/base/math/#Base.atanh-Tuple{Number}) |                                              Inverse hyperbolic |
|                                                                                                                                                                                                                                            `mean` | Available via `JuliaBUGS.BUGSPrimitives.mean(x::AbstractArray)` |


## From [LogExpFunctions](https://github.com/JuliaStats/LogExpFunctions.jl) {#From-LogExpFunctionshttps://github.com/JuliaStats/LogExpFunctions.jl}

|                                                                                 Function |                               Description |
| ----------------------------------------------------------------------------------------:| -----------------------------------------:|
|   [`cloglog`](https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.cloglog) | Complementary log-log: `log(-log(1 - x))` |
|   [`cexpexp`](https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.cexpexp) |  Inverse of `cloglog`: `1 - exp(-exp(x))` |
|       [`logit`](https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.logit) |                 Logit: `log(x / (1 - x))` |
| [`logistic`](https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.logistic) |   Logistic (sigmoid): `1 / (1 + exp(-x))` |


## From `JuliaBUGS.BUGSPrimitives` {#From-JuliaBUGS.BUGSPrimitives}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.equals' href='#JuliaBUGS.BUGSPrimitives.equals'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.equals</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
equals(x, y)
```


Returns 1 if $x$ is equal to $y$, 0 otherwise.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L1-L5" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.inprod' href='#JuliaBUGS.BUGSPrimitives.inprod'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.inprod</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
inprod(a, b)
```


Inner product of $a$ and $b$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L28-L32" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.inverse' href='#JuliaBUGS.BUGSPrimitives.inverse'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.inverse</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
inverse(m::AbstractMatrix)
```


Inverse of matrix $\mathbf{m}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L37-L41" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.logdet' href='#JuliaBUGS.BUGSPrimitives.logdet'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.logdet</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
logdet(::AbstractMatrix)
```


Logarithm of the determinant of matrix $\mathbf{v}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L46-L50" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.logfact' href='#JuliaBUGS.BUGSPrimitives.logfact'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.logfact</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
logfact(x)
```


Logarithm of the factorial of $x$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L55-L59" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.loggam' href='#JuliaBUGS.BUGSPrimitives.loggam'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.loggam</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
loggam(x)
```


Logarithm of the gamma function of $x$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L64-L68" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.icloglog' href='#JuliaBUGS.BUGSPrimitives.icloglog'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.icloglog</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
icloglog(x)
```


Inverse complementary log-log function of $x$. Alias for `cexpexp(x)`.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L10-L14" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.ilogit' href='#JuliaBUGS.BUGSPrimitives.ilogit'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.ilogit</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
ilogit(x)
```


Inverse logit function of $x$. Alias for `logistic(x)`.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L19-L23" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.mexp' href='#JuliaBUGS.BUGSPrimitives.mexp'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.mexp</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
mexp(x::AbstractMatrix)
```


Matrix exponential of $\mathbf{x}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L73-L77" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.phi' href='#JuliaBUGS.BUGSPrimitives.phi'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.phi</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
phi(x)
```


Cumulative distribution function (CDF) of the standard normal distribution evaluated at $x$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L82-L86" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.probit' href='#JuliaBUGS.BUGSPrimitives.probit'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.probit</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
probit
```


Inverse of [`phi`](/api/functions#JuliaBUGS.BUGSPrimitives.phi).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L91-L95" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.pow' href='#JuliaBUGS.BUGSPrimitives.pow'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.pow</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
pow(a, b)
```


Return $a$ raised to the power of $b$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L100-L104" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.rank' href='#JuliaBUGS.BUGSPrimitives.rank'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.rank</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
rank(v::AbstractVector, i::Integer)
```


Return the rank of the $i$-th element of $\mathbf{v}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L109-L113" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.ranked' href='#JuliaBUGS.BUGSPrimitives.ranked'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.ranked</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
ranked(v::AbstractVector, i::Integer)
```


Return the $i$-th element of $\mathbf{v}$ sorted in ascending order.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L118-L122" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.sd' href='#JuliaBUGS.BUGSPrimitives.sd'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.sd</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
sd(v::AbstractVector)
```


Return the standard deviation of the input vector $\mathbf{v}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L127-L131" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.softplus' href='#JuliaBUGS.BUGSPrimitives.softplus'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.softplus</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
softplus(x)
```


Return the softplus function of `x`, defined as $\log(1 + \exp(x))$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L136-L140" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives._step' href='#JuliaBUGS.BUGSPrimitives._step'><span class="jlbinding">JuliaBUGS.BUGSPrimitives._step</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
_step(x)
```


Return 1 if $x$ is greater than 0, and 0 otherwise.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L145-L149" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arcsin' href='#JuliaBUGS.BUGSPrimitives.arcsin'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arcsin</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arcsin(x)
```


See [`asin`](https://docs.julialang.org/en/v1/base/math/#Base.asin-Tuple{Number}).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L154-L158" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arcsinh' href='#JuliaBUGS.BUGSPrimitives.arcsinh'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arcsinh</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arcsinh(x)
```


See [`asinh`](https://docs.julialang.org/en/v1/base/math/#Base.asinh-Tuple{Number}).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L163-L167" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arccos' href='#JuliaBUGS.BUGSPrimitives.arccos'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arccos</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arccos(x)
```


See [`acos`](https://docs.julialang.org/en/v1/base/math/#Base.acos-Tuple{Number}).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L172-L176" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arccosh' href='#JuliaBUGS.BUGSPrimitives.arccosh'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arccosh</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arccosh(x)
```


See [`acosh`](https://docs.julialang.org/en/v1/base/math/#Base.acosh-Tuple{Number}).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L181-L185" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arctan' href='#JuliaBUGS.BUGSPrimitives.arctan'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arctan</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arctan(x)
```


See [`atan`](https://docs.julialang.org/en/v1/base/math/#Base.atan-Tuple{Number}).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L190-L194" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arctanh' href='#JuliaBUGS.BUGSPrimitives.arctanh'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arctanh</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arctanh(x)
```


See [`atanh`](https://docs.julialang.org/en/v1/base/math/#Base.atanh-Tuple{Number}).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/BUGSPrimitives/functions.jl#L199-L203" target="_blank" rel="noreferrer">source</a></Badge>

</details>

