export dnorm,
    dlogis,
    dt,
    ddexp,
    dflat,
    dexp,
    dgamma,
    dchisqr,
    dweib,
    dlnorm,
    dggamma,
    dpar,
    dgev,
    dgpar,
    df,
    dunif,
    dbeta,
    dmnorm,
    dmt,
    dwish,
    ddirich,
    dbern,
    dbin,
    dcat,
    dpois,
    dgeom,
    dnegbin,
    dbetabin,
    dhyper,
    dmulti,
    censored_with_lower,
    censored_with_upper,
    truncated_with_lower,
    truncated_with_upper

### 
### Distributions
### 

###
### Continuous univariate, unrestricted range
### 

dnorm(mu, tau) = Normal(mu, 1 / sqrt(tau))

dlogis(μ, τ) = Logistic(μ, 1 / τ)

function dt(μ, τ, k)
    if μ != 1 || τ != 1
        error("Only μ = 1 and τ = 1 are supported for Student's t distribution.")
    end
    return TDist(k)
end

ddexp(μ, τ) = Laplace(μ, 1 / τ)

dflat() = DFlat()

###
### Continuous univariate, restricted to be positive
###
dexp(λ) = Exponential(1 / λ)

dgamma(a, b) = Gamma(a, 1 / b)

dchisqr(k) = Chisq(k)

dweib(a, b) = Weibull(a, 1 / b)

dlnorm(μ, τ) = LogNormal(μ, 1 / τ)

function var"gen.gamma"(a, b, c)
    if c != 1
        error("Only c = 1 is supported for generalized gamma distribution.")
    end
    return Gamma(a, 1 / b)
end
dggamma(a, b, c) = var"gen.gamma"(a, b, c)

dpar(a, b) = Pareto(a, b)

dgev(μ, σ, η) = GeneralizedExtremeValue(μ, σ, η)

dgpar(μ, σ, η) = GeneralizedPareto(μ, σ, η)

function df(n, m, μ, τ)
    if μ != 1 || τ != 1
        error("Only μ = 1 and τ = 1 are supported for F distribution.")
    end
    return FDist(n, m)
end

###
### Continuous univariate, restricted to a finite interval
###

dunif(a, b) = Uniform(a, b)

dbeta(a, b) = Beta(a, b)

###
### Continuous multivariate distributions
###

dmnorm(μ::Vector, T::Matrix) = MvNormal(μ, T)

dmt(μ::Vector, T::Matrix, k) = MvTDist(k, μ, T)

dwish(R::Matrix, k) = Wishart(k, R^(-1))

ddirich(θ::Vector) = Dirichlet(θ)

###
### Discrete univariate distributions
###

dbern(p) = Bernoulli(p)

dbin(p, n) = Binomial(n, p)

dcat(p) = Categorical(p)

dpois(θ) = Poisson(θ)

dgeom(θ) = Geometric(θ)

dnegbin(p, r) = NegativeBinomial(r, p)

dbetabin(a, b, n) = BetaBinomial(n, a, b)

function dhyper(n1, n2, m1, ψ)
    if ψ != 1
        error("Only ψ = 1 is supported for hypergeometric distribution.")
    end
    return Hypergeometric(n1, n2, m1)
end

###
### Discrete multivariate distributions
###

dmulti(θ::Vector, n) = Multinomial(n, θ)

""" 
    Truncated and Censored Functions
"""

censored_with_lower(d, l) = Distributions.censored(d; lower=l)
censored_with_upper(d, u) = Distributions.censored(d; upper=u)

truncated_with_lower(d, l) = Distributions.truncated(d; lower=l)
truncated_with_upper(d, u) = Distributions.truncated(d; upper=u)
