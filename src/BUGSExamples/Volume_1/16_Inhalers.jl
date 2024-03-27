name = "Inhaler: ordered categorical data"

model_def = @bugs begin
    # Construct individual response data from contingency table
    for i in 1:Ncum[1, 1]
        group[i] = 1
        for t in 1:T
            response[i, t] = pattern[1, t]
        end
    end
    for i in (Ncum[1, 1] + 1):Ncum[1, 2]
        group[i] = 2
        for t in 1:T
            response[i, t] = pattern[1, t]
        end
    end

    for k in 2:Npattern
        for i in (Ncum[k - 1, 2] + 1):Ncum[k, 1]
            group[i] = 1
            for t in 1:T
                response[i, t] = pattern[k, t]
            end
        end
        for i in (Ncum[k, 1] + 1):Ncum[k, 2]
            group[i] = 2
            for t in 1:T
                response[i, t] = pattern[k, t]
            end
        end
    end

    # Model
    for i in 1:N
        for t in 1:T
            for j in 1:Ncut
                # Cumulative probability of worse response than j
                logit(Q[i, t, j]) = -(a[j] + mu[group[i], t] + b[i])
            end

            # Probability of response = j
            p[i, t, 1] = 1 - Q[i, t, 1]
            for j in 2:Ncut
                p[i, t, j] = Q[i, t, j - 1] - Q[i, t, j]
            end
            p[i, t, (Ncut + 1)] = Q[i, t, Ncut]

            response[i, t] ~ dcat(p[i, t, :])
            var"cumulative.response"[i, t] = cumulative(response[i, t], response[i, t])
        end
        # Subject (random) effects
        b[i] ~ dnorm(0.0, tau)
    end

    # Fixed effects
    for g in 1:G
        for t in 1:T
            # logistic mean for group i in period t
            mu[g, t] = beta * treat[g, t] / 2 + pi * period[g, t] / 2 +
                       kappa * carry[g, t]
        end
    end
    beta ~ dnorm(0, 1.0E-06)
    pi ~ dnorm(0, 1.0E-06)
    kappa ~ dnorm(0, 1.0E-06)

    # ordered cut points for underlying continuous latent variable
    a[1] ~ truncated(dflat(), -1000, a[2])
    a[2] ~ truncated(dflat(), a[1], a[3])
    a[3] ~ truncated(dflat(), a[2], 1000)

    tau ~ dgamma(0.001, 0.001)
    sigma = sqrt(1 / tau)
    var"log.sigma" = log(sigma)
end

data = (
    N = 286,
    T = 2,
    G = 2,
    Npattern = 16,
    Ncut = 3,
    pattern = [1 1
               1 2
               1 3
               1 4
               2 1
               2 2
               2 3
               2 4
               3 1
               3 2
               3 3
               3 4
               4 1
               4 2
               4 3
               4 4],
    Ncum = [59 122
            157 170
            173 173
            175 175
            186 226
            253 268
            270 270
            271 271
            271 278
            278 280
            280 281
            281 281
            282 284
            285 285
            285 286
            286 286],
    treat = [1 -1; -1 1],
    period = [1 -1; 1 -1],
    carry = [0 -1; 0 1]
)

inits = (beta = 0, pi = 0, kappa = 0, a = [2, 3, 4], tau = 1)
inits_alternative = (beta = 1, pi = 1, kappa = 0, a = [3, 4, 5], tau = 0.1)

reference_results = nothing

inhalers = Example(name, model_def, data, inits, inits_alternative, reference_results)
