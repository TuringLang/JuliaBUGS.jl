Most of the [functions](https://www.multibugs.org/documentation/latest/Functions.html) from BUGS have been implemented. 

`JuliaBUGS` directly utilizes functions from the Julia Standard Library when they share the same names and functionalities. For functions not available in the Julia Standard Library and other popular libraries, we have developed equivalents within `JuliaBUGS.BUGSPrimitives`.

## Function defined in Julia Standard Library
```@docs
abs
exp
log
sqrt
trunc
min
max
sum
sort
sin
cos
tan
JuliaBUGS.BUGSPrimitives.mean
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
