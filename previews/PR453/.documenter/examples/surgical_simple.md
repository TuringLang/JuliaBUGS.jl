
# Surgical (simple): institutional ranking with independent rates {#Surgical-simple:-institutional-ranking-with-independent-rates}

Mortality rates following cardiac surgery in 12 hospitals, modelled with independent Beta(1, 1) priors on each hospital&#39;s failure rate. This is the &quot;simplistic&quot; model in BUGS Volume 1; the realistic counterpart pools information across hospitals via a random-effects logistic regression.

## Graphical Model {#Graphical-Model}
<doodle-bugs width="100%" height="600px" model="surgical"></doodle-bugs>


## Model {#Model}

::: tabs

== JuliaBUGS @bugs

```julia
@bugs begin
    for i in 1:N
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    end
end
```


== JuliaBUGS @model

```julia
@model function surgical_simple((; p), N, n, r)
    for i in 1:N
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    end
end
```


== BUGS

```julia
model {
    for (i in 1 : N) {
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    }
}
```


:::

## How to use this example {#How-to-use-this-example}

```julia
using JuliaBUGS
ex = JuliaBUGS.BUGSExamples.surgical_simple
model_def = include(JuliaBUGS.BUGSExamples.path(ex, "model.jl"))
model = compile(model_def, ex.data, ex.inits)
```

