struct LogisticBijector <: Bijectors.Bijector end

Bijectors.transform(::LogisticBijector, x::Real) = logistic(x)
Bijectors.transform(::Inverse{LogisticBijector}, x::Real) = logit(x)
Bijectors.logabsdet(::LogisticBijector, x::Real) = log(logistic(x)) + log(1 - logistic(x))

struct CExpExp <: Bijectors.Bijector end

Bijectors.transform(::CExpExp, x::Real) = icloglog(x)
Bijectors.transform(::Inverse{CExpExp}, x::Real) = cloglog(x)
Bijectors.logabsdet(::CExpExp, x::Real) = -log(cloglog(-x))

struct ExpBijector <: Bijectors.Bijector end

Bijectors.transform(::ExpBijector, x::Real) = exp(x)
Bijectors.transform(::Inverse{ExpBijector}, x::Real) = log(x)
Bijectors.logabsdet(::ExpBijector, x::Real) = x

struct Phi <: Bijectors.Bijector end

Bijectors.transform(::Phi, x::Real) = phi(x)
Bijectors.transform(::Inverse{Phi}, x::Real) = probit(x)
Bijectors.logabsdet(::Phi, x::Real) = -0.5 * (x^2 + log(2π))

bijector_of_link_function(::typeof(logit)) = LogisticBijector()
bijector_of_link_function(::typeof(cloglog)) = CExpExp()
bijector_of_link_function(::typeof(log)) = ExpBijector()
bijector_of_link_function(::typeof(probit)) = Phi()