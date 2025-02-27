name = "Rats: a normal hierarchical model"

model_def = @bugs begin
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(mu[i, j], var"tau.c")
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ dnorm(var"beta.c", var"beta.tau")
    end
    var"tau.c" ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(var"tau.c")
    var"alpha.c" ~ dnorm(0.0, 1.0e-6)
    var"alpha.tau" ~ dgamma(0.001, 0.001)
    var"beta.c" ~ dnorm(0.0, 1.0e-6)
    var"beta.tau" ~ dgamma(0.001, 0.001)
    alpha0 = var"alpha.c" - xbar * var"beta.c"
end

original = """
model{
    for(i in 1:N) {
        for(j in 1:T) {
            Y[i, j] ~ dnorm(mu[i, j], tau.c)
            mu[i, j] <- alpha[i] + beta[i] * (x[j] - xbar)
        }
        alpha[i] ~ dnorm(alpha.c, alpha.tau)
        beta[i] ~ dnorm(beta.c, beta.tau)
    }
    tau.c ~ dgamma(0.001, 0.001)
    sigma <- 1 / sqrt(tau.c)
    alpha.c ~ dnorm(0.0, 1.0E-6)
    alpha.tau ~ dgamma(0.001, 0.001)
    beta.c ~ dnorm(0.0, 1.0E-6)
    beta.tau ~ dgamma(0.001, 0.001)
    alpha0 <- alpha.c - xbar * beta.c
}
"""

data = (
    x = [8.0, 15.0, 22.0, 29.0, 36.0],
    xbar = 22,
    N = 30,
    T = 5,
    Y = [151 199 246 283 320
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
         153 200 244 286 324]
)

inits = (
    alpha = fill(250.0, 30),
    beta = fill(6.0, 30),
    var"alpha.c" = 150.0,
    var"beta.c" = 10.0,
    var"tau.c" = 1.0,
    var"alpha.tau" = 1.0,
    var"beta.tau" = 1.0
)
inits_alternative = (
    alpha = fill(25.0, 30),
    beta = fill(0.6, 30),
    var"alpha.c" = 150.0,
    var"beta.c" = 10.0,
    var"tau.c" = 0.1,
    var"alpha.tau" = 0.1,
    var"beta.tau" = 0.1
)

reference_results = (
    alpha0 = (mean = 106.6, std = 3.66),
    var"beta.c" = (mean = 6.186, std = 0.1086),
    sigma = (mean = 6.093, std = 0.4643)
)

rats = Example(name, model_def, original, data, inits, inits_alternative, reference_results)
