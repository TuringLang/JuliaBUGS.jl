# How does `@bugsast` work?

We provide a macro solution allowing users to directly use Julia code that corresponds to BUGS code:

```julia
@bugsast begin
    for i in 1:N
        Y[i] ~ dnorm(μ[i], τ)
        μ[i] = α + β * (x[i] - x̄)
    end
    τ ~ dgamma(0.001, 0.001)
    σ = 1 / sqrt(τ)
    logτ = log(τ)
    α = dnorm(0.0, 1e-6)
    β = dnorm(0.0, 1e-6)
end
```

BUGS syntax carries over almost one-to-one to Julia.

### Internal Macro Structure

The macro checks that only allowed syntactic forms are used and then applies some minor normalizations. The most prominent normalization is the conversion of stochastic statements (tildes) from `:call` expressions to first-class forms:

```julia
quote
    for i = 1:N
        $(Expr(:~, :(Y[i]), :(dnorm(μ[i], τ))))
        μ[i] = α + β * (x[i] - x̄)
    end
    $(Expr(:~, :τ, :(dgamma(0.001, 0.001))))
    σ = 1 / sqrt(τ)
    logτ = log(τ)
    α = dnorm(0.0, 1.0e-6)
    β = dnorm(0.0, 1.0e-6)
end
```

In addition, there is a string macro `bugsmodel` which should work with the original (R-like) BUGS syntax:

```julia
bugsmodel"""
    for (i in 1:5) {
        y[i] ~ dnorm(mu[i], tau)
        mu[i] <- alpha + beta*(x[i] - mean(x[]))
    }
    
    alpha ~ dflat()
    beta ~ dflat()
    tau <- 1/sigma2
    log(sigma2) <- 2*log.sigma
    log.sigma ~ dflat()
"""
```

Internally, this macro applies a couple of regex-based substitutions to convert the code to the equivalent Julia, uses `Meta.parse` to parse the result, and applies the same logic as `@bugsast`. We encourage users to write new programs using the Julia-native syntax for better debuggability and perks like syntax highlighting. However, in the case of testing out legacy programs, using the macro should work for copy-paste situations. All variable names are preventively wrapped in var-strings; this allows R-style names like `b.abd`.

### AST Structure

The core forms which translate from BUGS to Julia are preserved in the equivalent Julia `Expr`s (e.g., `:call`, `:for`, `:if`, `:=`, `:ref`). The resulting code aims to be as close to executable as possible. Special forms are converted to simplify pattern matching:

- `~` statements are parsed as `:call` by Julia, and get their own form (`dc[i] ~ dunif(0, 20)` → `(:~, (:ref, :dc, :i), (:call, :dunif, 0, 20))`).
- In logical assignments with link functions, the block on the right-hand side, automatically created by the Julia parser, is removed.
  The result is therefore an `:=` expression with a direct `:call` on the LHS.
- Censoring and truncation annotations are converted to `:censored` and `:truncated` forms (`dnorm(x, μ) C (, 10)` → `(:censored, (:call, :dnorm, :x, :μ), :nothing, 100)`).
  The left-out limits (`C (, 100)`) are filled with `nothing`.
  In `@bugsast`, you may just use normal calls `truncated(dist, l, r)` and `censored(dist, l, r)`, which will be raised to special forms automatically.
- Empty ranges are automatically filled with slices (`x[,]` → `(:ref, :x, :(:), :(:))`).

In addition, forms that have both a `:call` representation and their own lowered form are tried to be normalized to the latter; currently, this concerns `getindex` to `:ref`, and `:` to `:(:)`.  `LineNumberNode`s are stripped completely.

## Advanced Usage for Hackers

It should be reasonably easy to define anything else on top of this representation by using simple `if` statements and `Meta.isexpr`. Interpolation (`$(…)`) is allowed in `@bugsast`; the result of the macro is a `:quote` expression, in which the interpolations are just left as is. For example:

```julia
@bugsast begin
    x = $(myfunc(somevalue))
end
```

This will end up as:

```julia
quote
    x = $(myfunc(somevalue))
end
```

With quasi-quotation working as usual, this allows for even greater flexibility and customization. However, be cautious when using interpolation, as it may be possible to construct ASTs that bypass validation and do not correspond to valid BUGS programs, so use it with care.