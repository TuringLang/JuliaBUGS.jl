
Most of the [functions](https://www.multibugs.org/documentation/latest/Functions.html) from BUGS have been implemented. 

`JuliaBUGS` directly utilizes functions from the Julia Standard Library when they share the same names and functionalities. For functions not available in the Julia Standard Library and other popular libraries, we have developed equivalents within `JuliaBUGS.BUGSPrimitives`.

## Function defined in Julia Standard Library {#Function-defined-in-Julia-Standard-Library}

::: warning No keyword arguments syntax in BUGS

Please note that some functions listed may accept additional arguments (e.g. `trunc`) and/or keyword arguments (e.g. `sum`, `sort`, `mean`). However, at the moment `JuliaBUGS` only supports function arguments of type `Real` or `AbstractArray{Real}`. Furthermore, `JuliaBUGS` does not accommodate the use of keyword argument syntax. Thus, the default values for any optional or keyword arguments will be automatically applied.

:::

::: warning Missing docstring.

Missing docstring for `abs`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `exp(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `log(x::Number)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `sqrt(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `trunc`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `min(x::Real, y::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `max(x::Real, y::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `sum(x::AbstractArray)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `sort(x::AbstractArray)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `sin(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `cos(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `tan(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `asin(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `acos(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `atan(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `asinh(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `acosh(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `atanh(x::Real)`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `JuliaBUGS.BUGSPrimitives.mean(x::AbstractArray)`. Check Documenter&#39;s build log for details.

:::

## Function defined in [`LogExpFunctions`](https://github.com/JuliaStats/LogExpFunctions.jl) {#Function-defined-in-LogExpFunctionshttps://github.com/JuliaStats/LogExpFunctions.jl}

::: warning Missing docstring.

Missing docstring for `cloglog`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `cexpexp`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `logit`. Check Documenter&#39;s build log for details.

:::

::: warning Missing docstring.

Missing docstring for `logistic`. Check Documenter&#39;s build log for details.

:::

## Function defined in `JuliaBUGS.BUGSPrimitives` {#Function-defined-in-JuliaBUGS.BUGSPrimitives}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.equals' href='#JuliaBUGS.BUGSPrimitives.equals'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.equals</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
equals(x, y)
```


Returns 1 if $x$ is equal to $y$, 0 otherwise.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L1-L5" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.inprod' href='#JuliaBUGS.BUGSPrimitives.inprod'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.inprod</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
inprod(a, b)
```


Inner product of $a$ and $b$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L28-L32" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.inverse' href='#JuliaBUGS.BUGSPrimitives.inverse'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.inverse</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
inverse(m::AbstractMatrix)
```


Inverse of matrix $\mathbf{m}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L37-L41" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.logdet' href='#JuliaBUGS.BUGSPrimitives.logdet'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.logdet</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
logdet(::AbstractMatrix)
```


Logarithm of the determinant of matrix $\mathbf{v}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L46-L50" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.logfact' href='#JuliaBUGS.BUGSPrimitives.logfact'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.logfact</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
logfact(x)
```


Logarithm of the factorial of $x$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L55-L59" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.loggam' href='#JuliaBUGS.BUGSPrimitives.loggam'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.loggam</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
loggam(x)
```


Logarithm of the gamma function of $x$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L64-L68" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.icloglog' href='#JuliaBUGS.BUGSPrimitives.icloglog'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.icloglog</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
icloglog(x)
```


Inverse complementary log-log function of $x$. Alias for [`cexpexp(x)`](@ref).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L10-L14" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.ilogit' href='#JuliaBUGS.BUGSPrimitives.ilogit'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.ilogit</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
ilogit(x)
```


Inverse logit function of $x$. Alias for [`logistic(x)`](@ref).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L19-L23" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.mexp' href='#JuliaBUGS.BUGSPrimitives.mexp'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.mexp</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
mexp(x::AbstractMatrix)
```


Matrix exponential of $\mathbf{x}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L73-L77" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.phi' href='#JuliaBUGS.BUGSPrimitives.phi'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.phi</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
phi(x)
```


Cumulative distribution function (CDF) of the standard normal distribution evaluated at $x$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L82-L86" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.probit' href='#JuliaBUGS.BUGSPrimitives.probit'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.probit</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
probit
```


Inverse of [`phi`](/api/functions#JuliaBUGS.BUGSPrimitives.phi).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L91-L95" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.pow' href='#JuliaBUGS.BUGSPrimitives.pow'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.pow</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
pow(a, b)
```


Return $a$ raised to the power of $b$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L100-L104" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.rank' href='#JuliaBUGS.BUGSPrimitives.rank'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.rank</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
rank(v::AbstractVector, i::Integer)
```


Return the rank of the $i$-th element of $\mathbf{v}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L109-L113" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.ranked' href='#JuliaBUGS.BUGSPrimitives.ranked'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.ranked</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
ranked(v::AbstractVector, i::Integer)
```


Return the $i$-th element of $\mathbf{v}$ sorted in ascending order.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L118-L122" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.sd' href='#JuliaBUGS.BUGSPrimitives.sd'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.sd</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
sd(v::AbstractVector)
```


Return the standard deviation of the input vector $\mathbf{v}$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L127-L131" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.softplus' href='#JuliaBUGS.BUGSPrimitives.softplus'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.softplus</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
softplus(x)
```


Return the softplus function of `x`, defined as $\log(1 + \exp(x))$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L136-L140" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives._step' href='#JuliaBUGS.BUGSPrimitives._step'><span class="jlbinding">JuliaBUGS.BUGSPrimitives._step</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
_step(x)
```


Return 1 if $x$ is greater than 0, and 0 otherwise.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L145-L149" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arcsin' href='#JuliaBUGS.BUGSPrimitives.arcsin'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arcsin</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arcsin(x)
```


See [`asin`](@ref%20Base.Math.asin).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L154-L158" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arcsinh' href='#JuliaBUGS.BUGSPrimitives.arcsinh'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arcsinh</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arcsinh(x)
```


See [`asinh`](@ref%20Base.Math.asinh).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L163-L167" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arccos' href='#JuliaBUGS.BUGSPrimitives.arccos'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arccos</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arccos(x)
```


See [`acos`](@ref%20Base.Math.acos).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L172-L176" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arccosh' href='#JuliaBUGS.BUGSPrimitives.arccosh'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arccosh</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arccosh(x)
```


See [`acosh`](@ref%20Base.Math.acosh).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L181-L185" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arctan' href='#JuliaBUGS.BUGSPrimitives.arctan'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arctan</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arctan(x)
```


See [`atan`](@ref%20Base.Math.atan).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L190-L194" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.arctanh' href='#JuliaBUGS.BUGSPrimitives.arctanh'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.arctanh</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
arctanh(x)
```


See [`atanh`](@ref%20Base.Math.atanh).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/e1350c4ebc29dec0f55680acbe864435d0a74857/JuliaBUGS/src/BUGSPrimitives/functions.jl#L199-L203" target="_blank" rel="noreferrer">source</a></Badge>

</details>

