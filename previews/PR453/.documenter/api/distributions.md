<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dnorm' href='#JuliaBUGS.BUGSPrimitives.dnorm'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dnorm</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dnorm(μ, τ)
```


Returns an instance of [Normal](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Normal)  with mean $μ$ and standard deviation $\frac{1}{√τ}$. 

$$p(x|μ,τ) = \sqrt{\frac{τ}{2π}} e^{-τ \frac{(x-μ)^2}{2}}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L1-L10" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dlogis' href='#JuliaBUGS.BUGSPrimitives.dlogis'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dlogis</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dlogis(μ, τ)
```


Return an instance of [Logistic](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Logistic)  with location parameter $μ$ and scale parameter $\frac{1}{√τ}$.

$$p(x|μ,τ) = \frac{\sqrt{τ} e^{-\sqrt{τ}(x-μ)}}{(1+e^{-\sqrt{τ}(x-μ)})^2}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L20-L29" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dt' href='#JuliaBUGS.BUGSPrimitives.dt'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dt</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dt(μ, τ, ν)
```


If $μ = 0$ and $σ = 1$, the function returns an instance of [TDist](https://juliastats.org/Distributions.jl/stable/univariate/#Distributions.TDist)  with $ν$ degrees of freedom, location $μ$, and scale $σ = \frac{1}{\sqrt{τ}}$. Otherwise, it returns an instance of [`TDistShiftedScaled`](/api/distributions#JuliaBUGS.BUGSPrimitives.TDistShiftedScaled).

$$p(x|ν,μ,σ) = \frac{Γ((ν+1)/2)}{Γ(ν/2) \sqrt{νπσ}}
\left(1+\frac{1}{ν}\left(\frac{x-μ}{σ}\right)^2\right)^{-\frac{ν+1}{2}}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L62-L72" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.TDistShiftedScaled' href='#JuliaBUGS.BUGSPrimitives.TDistShiftedScaled'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.TDistShiftedScaled</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
TDistShiftedScaled(ν, μ, σ)
```


Student&#39;s t-distribution with $ν$ degrees of freedom, location $μ$, and scale $σ$. 

This struct allows for a shift (determined by $μ$) and a scale (determined by $σ$) of the standard  Student&#39;s t-distribution provided by the [Distributions.jl](https://github.com/JuliaStats/Distributions.jl)  package. 

Only `pdf` and `logpdf` are implemented for this distribution.

**See Also**

[TDist](https://juliastats.org/Distributions.jl/stable/univariate/#Distributions.TDist)


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L35-L48" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.ddexp' href='#JuliaBUGS.BUGSPrimitives.ddexp'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.ddexp</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
ddexp(μ, τ)
```


Return an instance of [Laplace (Double Exponential)](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Laplace)  with location $μ$ and scale $\frac{1}{\sqrt{τ}}$.

$$p(x|μ,τ) = \frac{\sqrt{τ}}{2} e^{-\sqrt{τ} |x-μ|}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L82-L91" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dflat' href='#JuliaBUGS.BUGSPrimitives.dflat'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dflat</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dflat()
```


Returns an instance of [`Flat`](/api/distributions#JuliaBUGS.BUGSPrimitives.Flat) or [`TruncatedFlat`](/api/distributions#JuliaBUGS.BUGSPrimitives.TruncatedFlat) if truncated.

`Flat` represents a flat (uniform) prior over the real line, which is an improper distribution. And  `TruncatedFlat` represents a truncated version of the `Flat` distribution.

Only `pdf`, `logpdf`, `minimum`, and `maximum` are implemented for these Distributions.

When use in a model, the parameters always need to be initialized.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L97-L108" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.Flat' href='#JuliaBUGS.BUGSPrimitives.Flat'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.Flat</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
Flat
```


The flat distribution mimicking the behavior of the `dflat` distribution in the BUGS family of softwares.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L111-L115" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.TruncatedFlat' href='#JuliaBUGS.BUGSPrimitives.TruncatedFlat'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.TruncatedFlat</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
TruncatedFlat
```


Truncated version of the [`Flat`](/api/distributions#JuliaBUGS.BUGSPrimitives.Flat) distribution.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L144-L148" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dexp' href='#JuliaBUGS.BUGSPrimitives.dexp'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dexp</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dexp(λ)
```


Returns an instance of [Exponential](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Exponential)  with rate $\frac{1}{λ}$.

$$p(x|λ) = λ e^{-λ x}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L176-L185" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dchisqr' href='#JuliaBUGS.BUGSPrimitives.dchisqr'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dchisqr</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dchisqr(k)
```


Returns an instance of [Chi-squared](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Chisq)  with $k$ degrees of freedom.

$$p(x|k) = \frac{1}{2^{k/2} Γ(k/2)} x^{k/2 - 1} e^{-x/2}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L205-L214" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dweib' href='#JuliaBUGS.BUGSPrimitives.dweib'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dweib</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dweib(a, b)
```


Returns an instance of [Weibull](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Weibull)  distribution object with shape parameter $a$ and scale parameter $\frac{1}{b}$.

The Weibull distribution is a common model for event times. The hazard or instantaneous risk of the event  is $abx^{a-1}$. For $a < 1$ the hazard decreases with $x$; for $a > 1$ it increases.  $a = 1$ results in the exponential distribution with constant hazard.

$$p(x|a,b) = abx^{a-1}e^{-b x^a}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L219-L232" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dlnorm' href='#JuliaBUGS.BUGSPrimitives.dlnorm'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dlnorm</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dlnorm(μ, τ)
```


Returns an instance of [LogNormal](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.LogNormal)  with location $μ$ and scale $\frac{1}{\sqrt{τ}}$.

$$p(x|μ,τ) = \frac{\sqrt{τ}}{x\sqrt{2π}} e^{-τ/2 (\log(x) - μ)^2}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L237-L246" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dgamma' href='#JuliaBUGS.BUGSPrimitives.dgamma'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dgamma</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dgamma(a, b)
```


Returns an instance of [Gamma](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Gamma)  with shape $a$ and scale $\frac{1}{b}$.

$$p(x|a,b) = \frac{b^a}{Γ(a)} x^{a-1} e^{-bx}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L190-L199" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dpar' href='#JuliaBUGS.BUGSPrimitives.dpar'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dpar</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dpar(a, b)
```


Returns an instance of [Pareto](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Pareto)  with scale parameter $b$ and shape parameter $a$.

$$p(x|a,b) = \frac{a b^a}{x^{a+1}}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L251-L260" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dgev' href='#JuliaBUGS.BUGSPrimitives.dgev'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dgev</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dgev(μ, σ, η)
```


Returns an instance of [GeneralizedExtremeValue](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.GeneralizedExtremeValue)  with location $μ$, scale $σ$, and shape $η$.

$$p(x|μ,σ,η) = \frac{1}{σ} \left(1 + η \frac{x - μ}{σ}\right)^{-\frac{1}{η} - 1} e^{-\left(1 + η \frac{x - μ}{σ}\right)^{-\frac{1}{η}}}$$

where $\frac{η(x - μ)}{σ} > -1$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L265-L276" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dgpar' href='#JuliaBUGS.BUGSPrimitives.dgpar'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dgpar</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dgpar(μ, σ, η)
```


Returns an instance of [GeneralizedPareto](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.GeneralizedPareto)  with location $μ$, scale $σ$, and shape $η$.

$$p(x|μ,σ,η) = \frac{1}{σ} (1 + η ((x - μ)/σ))^{-1/η - 1}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L289-L298" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.df' href='#JuliaBUGS.BUGSPrimitives.df'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.df</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
df(n, m, μ=0, τ=1)
```


Returns an instance of [F-distribution](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.FDist)  object with $n$ and $m$ degrees of freedom, location $μ$, and scale $τ$. This function is only valid when $μ = 0$ and $τ = 1$,

$$p(x|n, m, μ, τ) = \frac{\Gamma\left(\frac{n+m}{2}\right)}{\Gamma\left(\frac{n}{2}\right) \Gamma\left(\frac{m}{2}\right)} \left(\frac{n}{m}\right)^{\frac{n}{2}} \sqrt{τ} \left(\sqrt{τ}(x - μ)\right)^{\frac{n}{2}-1} \left(1 + \frac{n \sqrt{τ}(x-μ)}{m}\right)^{-\frac{n+m}{2}}$$

where $\frac{n \sqrt{τ} (x - μ)}{m} > -1$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L303-L314" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dunif' href='#JuliaBUGS.BUGSPrimitives.dunif'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dunif</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dunif(a, b)
```


Returns an instance of [Uniform](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Uniform)  with lower bound $a$ and upper bound $b$.

$$p(x|a,b) = \frac{1}{b - a}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L333-L342" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dbeta' href='#JuliaBUGS.BUGSPrimitives.dbeta'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dbeta</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dbeta(a, b)
```


Returns an instance of [Beta](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Beta)  with shape parameters $a$ and $b$.

$$p(x|a,b) = \frac{\Gamma(a + b)}{\Gamma(a)\Gamma(b)} x^{a-1} (1 - x)^{b-1}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L347-L356" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dmnorm' href='#JuliaBUGS.BUGSPrimitives.dmnorm'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dmnorm</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dmnorm(μ::AbstractVector, T::AbstractMatrix)
```


Returns an instance of [Multivariate Normal](https://juliastats.org/Distributions.jl/latest/multivariate/#Distributions.MvNormal)  with mean vector `μ` and covariance matrix $T^{-1}$.

$$p(x|μ,T) = (2π)^{-k/2} |T|^{1/2} e^{-1/2 (x-μ)' T (x-μ)}$$

where $k$ is the dimension of `x`.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L365-L375" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dmt' href='#JuliaBUGS.BUGSPrimitives.dmt'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dmt</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dmt(μ::AbstractVector, T::AbstractMatrix, k)
```


Returns an instance of [Multivariate T](https://github.com/JuliaStats/Distributions.jl/blob/master/src/multivariate/mvtdist.jl)  with mean vector $μ$, scale matrix $T^{-1}$, and $k$ degrees of freedom.

$$p(x|k,μ,Σ) = \frac{\Gamma((k+d)/2)}{\Gamma(k/2) (k\pi)^{p/2} |Σ|^{1/2}} \left(1 + \frac{1}{k} (x-μ)^T Σ^{-1} (x-μ)\right)^{-\frac{k+p}{2}}$$

where $p$ is the dimension of $x$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L380-L390" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dwish' href='#JuliaBUGS.BUGSPrimitives.dwish'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dwish</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dwish(R::AbstractMatrix, k)
```


Returns an instance of [Wishart](https://juliastats.org/Distributions.jl/latest/matrix/#Distributions.Wishart)  with $k$ degrees of freedom and the scale matrix $T^{-1}$.

$$p(X|R,k) = |R|^{k/2} |X|^{(k-p-1)/2} e^{-(1/2) tr(RX)} / (2^{kp/2} Γ_p(k/2))$$

where $p$ is the dimension of $X$, and it should be less than or equal to $k$. 


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L395-L405" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.ddirich' href='#JuliaBUGS.BUGSPrimitives.ddirich'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.ddirich</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
ddirich(θ::AbstractVector)
```


Return an instance of [Dirichlet](https://juliastats.org/Distributions.jl/latest/multivariate/#Distributions.Dirichlet)  with parameters $θ_i$.

$$p(x|θ) = \frac{Γ(\sum θ)}{∏ Γ(θ)} ∏ x_i^{θ_i - 1}$$

where $\theta_i > 0, x_i \in [0, 1], \sum_i x_i = 1$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L417-L427" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dbern' href='#JuliaBUGS.BUGSPrimitives.dbern'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dbern</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dbern(p)
```


Return an instance of [Bernoulli](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Bernoulli)  with success probability `p`.

$$p(x|p) = p^x (1 - p)^{1-x}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L432-L441" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dbin' href='#JuliaBUGS.BUGSPrimitives.dbin'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dbin</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dbin(p, n)
```


Returns an instance of [Binomial](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Binomial)  with number of trials `n` and success probability `p`.

$$p(x|n,p) = \binom{n}{x} p^x (1 - p)^{n-x}$$

end

where $\theta \in [0, 1], n \in \mathbb{Z}^+,$ and $x = 0, \ldots, n$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L446-L457" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dcat' href='#JuliaBUGS.BUGSPrimitives.dcat'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dcat</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dcat(p)
```


Returns an instance of [Categorical](https://juliastats.org/Distributions.jl/latest/multivariate/#Distributions.Categorical)  with probabilities `p`.

$$p(x|p) = p[x]$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L462-L471" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dpois' href='#JuliaBUGS.BUGSPrimitives.dpois'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dpois</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dpois(θ)
```


Returns an instance of [Poisson](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Poisson)  with mean (and variance) `θ`.

$$p(x|θ) = e^{-θ} θ^x / x!$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L476-L485" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dgeom' href='#JuliaBUGS.BUGSPrimitives.dgeom'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dgeom</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dgeom(θ)
```


Returns an instance of [Geometric](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Geometric)  with success probability `θ`.

$$p(x|θ) = (1 - θ)^{x-1} θ$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L490-L499" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dnegbin' href='#JuliaBUGS.BUGSPrimitives.dnegbin'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dnegbin</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dnegbin(p, r)
```


Returns an instance of [Negative Binomial](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.NegativeBinomial)  with number of failures `r` and success probability `p`.

$$P(x|r,p) = \binom{x + r - 1}{x} (1 - p)^x p^r$$

where $x \in \mathbb{Z}^+$.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L504-L515" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dbetabin' href='#JuliaBUGS.BUGSPrimitives.dbetabin'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dbetabin</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dbetabin(a, b, n)
```


Returns an instance of [Beta Binomial](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.BetaBinomial)  with number of trials `n` and shape parameters `a` and `b`.

$$P(x|a, b, n) = \frac{\binom{n}{x} \binom{a + b - 1}{a + x - 1}}{\binom{a + b + n - 1}{n}}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L520-L529" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dhyper' href='#JuliaBUGS.BUGSPrimitives.dhyper'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dhyper</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dhyper(n₁, n₂, m₁, ψ=1)
```


Returns an instance of [Hypergeometric](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Hypergeometric).  This distribution is used when sampling without replacement from a population consisting of  $n₁$ successes and $n₂$ failures, with $m₁$ being the number of trials or the sample size.  The function currently only allows for $ψ = 1$.

$$p(x | n₁, n₂, m₁, \psi) = \frac{\binom{n₁}{x} \binom{n₂}{m₁ - x} \psi^x}{\sum_{i=u_0}^{u_1} \binom{n1}{i} \binom{n2}{m₁ - i} \psi^i}$$

where $u_0 = \max(0, m₁-n₂), u_1 = \min(n₁,m₁),$ and $u_0 \leq x \leq u_1$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L534-L546" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSPrimitives.dmulti' href='#JuliaBUGS.BUGSPrimitives.dmulti'><span class="jlbinding">JuliaBUGS.BUGSPrimitives.dmulti</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dmulti(θ::AbstractVector, n)
```


Returns an instance [Multinomial](https://juliastats.org/Distributions.jl/latest/multivariate/#Distributions.Multinomial)  with number of trials `n` and success probabilities `θ`.

$$P(x|n,θ) = \frac{n!}{∏_{r} x_{r}!} ∏_{r} θ_{r}^{x_{r}}$$


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/BUGSPrimitives/distributions.jl#L554-L563" target="_blank" rel="noreferrer">source</a></Badge>

</details>

