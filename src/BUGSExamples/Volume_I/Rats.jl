# https://chjackson.github.io/openbugsdoc/Examples/Rats.html

"""
    Rats

This example is taken from section 6 of *Gelfand et al. (1990)*, and concerns 30 young rats whose
weights were measured weekly for five weeks. Part of the data is shown below, where ``Y_{ij}`` is the
weight of the ``i^{th}`` rat measured at age ``x_j``.

# Table: Weights ``Y_{ij}`` of rat ``i`` on day ``x_j``

| Rat   | `x_j=8` | `x_j=15` | `x_j=22` | `x_j=29` | `x_j=36` |
|-------|---------|----------|----------|----------|----------|
| Rat 1 |     151 |      199 |      246 |      283 |      320 |
| Rat 2 |     145 |      199 |      249 |      293 |      354 |
| ...   |     ... |      ... |      ... |      ... |      ... |
| Rat 30|     153 |      200 |      244 |      286 |      324 |

A plot of the 30 growth curves suggests some evidence of downward curvature.

The model is essentially a random effects linear growth curve

```math
Y_{ij} \\sim Normal(a_i + b_i (x_j - \\bar{x}), tau_c)
a_i \\sim Normal(a_c, tau_a)
b_i \\sim Normal(b_c, tau_b)
```

where `\bar{x} = 22`, and `τ` represents the precision (`1/variance`) of a normal distribution. We note the
absence of a parameter representing correlation between `a_i` and `b_i` unlike in *Gelfand et al. (1990)*.
However, see the *Birats* example in Volume 2 which does explicitly model the covariance
between `a_i` and `b_i`. For now, we standardize the `x_j`'s around their mean to reduce dependence
between `a_i` and `b_i` in their likelihood: in fact, for the full balanced data, complete independence is
achieved. (Note that, in general, prior independence does not force the posterior distributions to
be independent).

`a_c`, `τ_a`, `b_c`, `τ_b`, `τ_c` are given independent "noninformative" priors. Interest particularly focuses on
the intercept at zero time (birth), denoted `a_0 = a_c - b_c · \bar{x}`.
"""
rats = (
    name="Rats",
    model_def=@bugs(begin
        for  i in 1 : N    
            for  j in 1 : T    
            Y[i , j] ~ dnorm(mu[i , j],var"tau.c")
            mu[i , j] = alpha[i] + beta[i] * (x[j] - xbar)
             end
            alpha[i] ~ dnorm(var"alpha.c",var"alpha.tau")
            beta[i] ~ dnorm(var"beta.c",var"beta.tau")
         end
        var"tau.c" ~ dgamma(0.001,0.001)
        sigma = 1 / sqrt(var"tau.c")
        var"alpha.c" ~ dnorm(0.0,1.0E-6)   
        var"alpha.tau" ~ dgamma(0.001,0.001)
        var"beta.c" ~ dnorm(0.0,1.0E-6)
        var"beta.tau" ~ dgamma(0.001,0.001)
        alpha0 = var"alpha.c" - xbar * var"beta.c"
    end),
    data=(
        x=[8.0, 15.0, 22.0, 29.0, 36.0],
        xbar=22,
        N=30,
        T=5,
        Y=[
            151 199 246 283 320
            145 199 249 293 354
            147 214 263 312 328
            155 200 237 272 297
            135 188 230 280 323
            159 210 252 298 331
            141 189 231 275 305
            159 201 248 297 338
            177 236 285 350 376
            134 182 220 260 296
            160 208 261 313 352
            143 188 220 273 314
            154 200 244 289 325
            171 221 270 326 358
            163 216 242 281 312
            160 207 248 288 324
            142 187 234 280 316
            156 203 243 283 317
            157 212 259 307 336
            152 203 246 286 321
            154 205 253 298 334
            139 190 225 267 302
            146 191 229 272 302
            157 211 250 285 323
            132 185 237 286 331
            160 207 257 303 345
            169 216 261 295 333
            157 205 248 289 316
            137 180 219 258 291
            153 200 244 286 324
        ],
    ),
    inits=[
        (
            alpha=ones(Integer, 30) .* 250,
            beta=ones(Integer, 30) .* 6,
            var"alpha.c"=150,
            var"beta.c"=10,
            var"tau.c"=1,
            var"alpha.tau"=1,
            var"beta.tau"=1,
        ),
        (
            alpha=ones(Integer, 30) .* 25,
            beta=ones(Integer, 30) .* 0.6,
            var"alpha.c"=15,
            var"beta.c"=1,
            var"tau.c"=0.1,
            var"alpha.tau"=0.1,
            var"beta.tau"=0.1,
        ),
    ],
    reference_results=(
        alpha0=(mean=106.6, std=3.66),
        var"beta.c"=(mean=6.186, std=0.1086),
        sigma=(mean=6.093, std=0.4643),
    ),
)
