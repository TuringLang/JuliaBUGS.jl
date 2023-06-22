struct Logistic <: Bijectors.Bijector end

Bijectors.transform(::Logistic, x::Real) = logistic(x)
Bijectors.transform(::Inverse{Logistic}, x::Real) = logit(x)
Bijectors.logabsdet(::Logistic, x::Real) = log(logistic(x)) + log(1 - logistic(x))

struct CExpExp <: Bijectors.Bijector end

Bijectors.transform(::CExpExp, x::Real) = icloglog(x)
Bijectors.transform(::Inverse{CExpExp}, x::Real) = cloglog
Bijectors.logabsdet(::CExpExp, x::Real) = -log(cloglog(-x))

struct Exp <: Bijectors.Bijector end

Bijectors.transform(::Exp, x::Real) = exp(x)
Bijectors.transform(::Inverse{Exp}, x::Real) = log(x)
Bijectors.logabsdet(::Exp, x::Real) = x

struct Phi <: Bijectors.Bijector end

Bijectors.transform(::Phi, x::Real) = phi(x)
Bijectors.transform(::Inverse{Phi}, x::Real) = probit(x)
Bijectors.logabsdet(::Phi, x::Real) = -0.5 * (x^2 + log(2π))
