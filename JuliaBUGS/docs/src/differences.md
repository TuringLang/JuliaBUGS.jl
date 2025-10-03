# Differences From Other BUGS Implementations

There exist many implementations of BUGS, notably [`WinBUGS`](https://www.mrc-bsu.cam.ac.uk/software/), [`OpenBUGS`](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html), [`MultiBUGS`](https://www.multibugs.org/documentation/latest/), [`JAGS`](https://mcmc-jags.sourceforge.io/), and [`nimble`](https://r-nimble.org/).

This section aims to outline some differences between JuliaBUGS and other BUGS implementations.
This comparison is not exhaustive, and we welcome any further discussion and reports on the matter.

## Use of generic function in distribution functions

In `WinBUGS`, `OpenBUGS`, and `MultiBUGS`, the arguments to distribution functions are typically restricted to variables or constants, not general expressions. JuliaBUGS, however, allows for more flexibility in these arguments.

For example, the following expressions are allowed in all BUGS implementations, including JuliaBUGS (assuming `y = [1, 2, 3]`):

```S
model {
 x ~ dnorm(y[y[2]], 1)
}

model {
  x ~ dnorm(y[y[2]+1], 1)
}
```

However, JuliaBUGS allows more flexibility in these arguments. The following expressions, which are not allowed in traditional BUGS implementations, are permitted in JuliaBUGS:

```S
model {
 x ~ dnorm(y[1] + 1, 1)
}

model {
 x ~ dnorm(sum(y[1:2]), 1)
}

model {
 x ~ dnorm(y[sum(y[1:2])], 1)
}
```

## `cumulative`, `density`, and `deviance` Functions

In [`OpenBUGS`](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html), there are several functions for working with distributions:

* `cumulative(s1, s2)`: Computes the tail area (cumulative distribution function) of the distribution of s1 up to the value of s2. s1 must be a stochastic node, and s1 and s2 can be the same.
* `density(s1, s2)`: Computes the density function of the distribution of s1 at the value of s2. s1 must be a stochastic node supplied as data, and s1 and s2 can be the same.
* `deviance(s1, s2)`: Computes the deviance of the distribution of s1 at the value of s2. s1 must be a stochastic node supplied as data, and s1 and s2 can be the same.

In [`MultiBUGS`](https://www.multibugs.org/documentation/latest/Functions.html), these functions have been replaced with the `cdf.dist`, `pdf.dist`, and `dev.dist` family of functions.

In JuliaBUGS, we don't have these functions directly, but similar functionality can be achieved using the `Distributions.jl` package:

* The [`cdf`](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.cdf-Tuple{UnivariateDistribution,%20Real}) function computes the cumulative distribution function of a given univariate distribution at a specified value.
* The [`pdf`](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.pdf-Tuple{UnivariateDistribution,%20Real}) function computes the probability density function of a given univariate distribution at a specified value.
* JuliaBUGS does not currently support a `deviance` function equivalent to the one in OpenBUGS.

### Example

The `cdf` and `pdf` functions from the `Distributions.jl` are simple to use: the first argument is the distribution, and the second argument is the value at which to evaluate the function.

An OpenBUGS program like

```S
model {
    x ~ dnorm(0, 1)
    cumulative.x = cumulative(x, x)
}
```

will need to be rewritten to:

```julia
@bugs begin
    x ~ Normal(0, 1)
    cumulative_x = cdf(Normal(0, 1), x)
end
```

## Use `:` for slicing when using Julia Syntax

In the original BUGS language, slicing is performed using syntax like `x[, ]`, which selects all elements from both the first and second dimensions.

The `@bugs` macro will automatically insert a `:` when given `x[]`, however, Julia parser will throw an error if it encounters `x[, ]`, so when using the @bugs macro in JuliaBUGS, users must explicitly use the `Colon (:)` operator for slicing. For example, to select all elements from both dimensions of an array x, you would write `x[:, :]`.

## Link functions

BUGS supports four link functions: `log`, `logit`, `cloglog`, and `probit`. These functions are used to support Generalized Linear Models and, in some cases, to transform random variables with constrained support to the real line.

For instance, the `Seeds` example features logistic regression, and the model definition is

```S
model
{
    for( i in 1 : N ) {
        r[i] ~ dbin(p[i],n[i])
        beta[i] ~ dnorm(0.0,tau)
        logit(p[i]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + beta[i]
    }
    alpha0 ~ dnorm(0.0,1.0E-6)
    alpha1 ~ dnorm(0.0,1.0E-6)
    alpha2 ~ dnorm(0.0,1.0E-6)
    alpha12 ~ dnorm(0.0,1.0E-6)
    sigma ~ dunif(0,10)
    tau <- 1 / pow(sigma, 2)
}
```

JuliaBUGS inherits these functions, but it's important to note that the link function syntax is not supported when using the Julia-like syntax. The reason for this is that Julia uses the syntax `f(...) = ...` to define functions, and the link function syntax can be confusing in the Julia context.

Instead, users are advised to use the inverse functions of these link functions by calling them on the right-hand side (RHS) of the statement. The inverse functions are:

* `log` → `exp`
* `logit` → `logistic`
* `cloglog` → `cloglog`
* `probit` → `probit`

So the above model should be rewritten as

```julia
@bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0e-6)
    alpha1 ~ dnorm(0.0, 1.0e-6)
    alpha2 ~ dnorm(0.0, 1.0e-6)
    alpha12 ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```

(When the program is in the original BUGS syntax, the link function syntax is supported.)

It's also worth noting that JuliaBUGS uses [`Bijectors.jl`](https://turinglang.org/Bijectors.jl/dev/) to handle constrained parameters.

### Compare with `nimble`

In the BUGS language, link functions are only supported in logical assignments. However, `nimble` extends this functionality by allowing link functions to be used in stochastic assignments as well. `nimble` will creates new node as intermediate variables. JuliaBUGS doesn't currently support this syntax.
