export abs,
    cloglog,
    cos,
    equals,
    exp,
    inprod,
    # inverse,
    log,
    logdet,
    logfact,
    loggam,
    logit,
    icloglog,
    ilogit,
    max,
    mean,
    min,
    phi,
    pow,
    probit,
    sqrt,
    rank,
    ranked,
    round,
    sd,
    softplus,
    sort,
    _step,
    sum,
    trunc,
    sin,
    arcsin,
    arcsinh,
    cos,
    arccos,
    arccosh,
    tan,
    arctan,
    arctanh,
    mexp,
    var"eigen.vals"

###
### Standard functions
###

abs
cloglog
cos
equals(x, y) = x == y ? 1 : 0
exp
inprod(a, b) = a * b
inverse(v) = LinearAlgebra.inv(v);
log
logdet(v) = LinearAlgebra.logdet(v)
logfact(x) = log(factorial(x))
loggam(x) = loggamma(x)
logit
icloglog(x) = cexpexp(x)
ilogit(x) = logistic(x)
max
mean
min
phi(x) = Distributions.cdf(Normal(0, 1), x)
pow(a, b) = a^b
# probit # use the inverse function phi
sqrt
rank(v::Vector, i::Int) = sortperm(v)[i];
ranked(v::Vector, i::Int) = v[sortperm(v)[i]];
round
sd(v::Vector) = Statistics.std(v);
softplus(x) = log1pexp(x)
sort(v::Vector) = Base.sort(v);
_step(x) = ifelse(x > 0, 1, 0);
sum
trunc

###
### Trigonometric functions
###

sin
arcsin(x) = asin(x)
arcsinh(x) = asinh(x)
cos
arccos(x) = acos(x)
arccosh(x) = acosh(x)
tan
arctan(x) = atan(x)
arctanh(x) = atanh(x)

###
### Matrix Algebra
###

t(v::Vector) = v'
mexp(v::Matrix) = exp(v)
var"eigen.vals"(v::Matrix) = eigen(v).values

### 
### Model Checking
###

# replicate.post, replicate.prior, post.p.value, prior.p.value are not implemented, use facilities from MCMCChains instead
