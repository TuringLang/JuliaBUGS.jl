Most of the [functions](https://www.multibugs.org/documentation/latest/Functions.html) from BUGS have been implemented. 

`JuliaBUGS` directly utilizes functions from the Julia Standard Library when they share the same names and functionalities. For functions not available in the Julia Standard Library and other popular libraries, we have developed equivalents within `JuliaBUGS.BUGSPrimitives`.

## Function defined in Julia Standard Library

```@docs
abs(x::Real)
exp(x::Real)
log(x::Number)
sqrt(x::Real)
trunc
min(x::Real, y::Real)
max(x::Real, y::Real)
sum(x::AbstractArray)
sort(x::AbstractArray)
!!! warning
    `JuliaBUGS` does not allow keyword arguments syntax
sin(x::Real)
cos(x::Real)
tan(x::Real)
asin(x::Real)
acos(x::Real)
atan(x::Real)
asinh(x::Real)
acosh(x::Real)
atanh(x::Real)
JuliaBUGS.BUGSPrimitives.mean(x::AbstractArray)
```

## Function defined in [`LogExpFunctions`](https://github.com/JuliaStats/LogExpFunctions.jl)

```@docs
cloglog
cexpexp
logit
logistic
```

## Function defined in `JuliaBUGS.BUGSPrimitives`

```@docs
JuliaBUGS.BUGSPrimitives.equals
JuliaBUGS.BUGSPrimitives.inprod
JuliaBUGS.BUGSPrimitives.inverse
JuliaBUGS.BUGSPrimitives.logdet
JuliaBUGS.BUGSPrimitives.logfact
JuliaBUGS.BUGSPrimitives.loggam
JuliaBUGS.BUGSPrimitives.icloglog
JuliaBUGS.BUGSPrimitives.mexp
JuliaBUGS.BUGSPrimitives.phi
JuliaBUGS.BUGSPrimitives.pow
JuliaBUGS.BUGSPrimitives.rank
JuliaBUGS.BUGSPrimitives.ranked
JuliaBUGS.BUGSPrimitives.sd
JuliaBUGS.BUGSPrimitives.softplus
JuliaBUGS.BUGSPrimitives._step
JuliaBUGS.BUGSPrimitives.arcsin
JuliaBUGS.BUGSPrimitives.arcsinh
JuliaBUGS.BUGSPrimitives.arccos
JuliaBUGS.BUGSPrimitives.arccosh
JuliaBUGS.BUGSPrimitives.arctan
JuliaBUGS.BUGSPrimitives.arctanh
```
