# Base strict module with only whitelisted imports
module BUGSStrictBase

using ..BUGSPrimitives
using Distributions:
    Normal,
    LogNormal,
    Uniform,
    Beta,
    Gamma,
    Exponential,
    Chisq,
    TDist,
    Weibull,
    Pareto,
    Laplace,
    Logistic,
    InverseGamma,
    MvNormal,
    Wishart,
    InverseWishart,
    Dirichlet,
    Bernoulli,
    Binomial,
    Categorical,
    Poisson,
    NegativeBinomial,
    DiscreteUniform,
    Geometric,
    Hypergeometric,
    pdf,
    logpdf,
    cdf,
    logcdf,
    quantile,
    rand

# Re-export all BUGS primitives
for func in BUGSPrimitives.BUGS_FUNCTIONS
    @eval using ..BUGSPrimitives: $func
end

# Re-export all BUGS distribution constructors
for dist in BUGSPrimitives.BUGS_DISTRIBUTIONS
    @eval using ..BUGSPrimitives: $dist
end

end # module
