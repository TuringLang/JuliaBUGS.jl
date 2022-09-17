# https://chjackson.github.io/openbugsdoc/Examples/Inhalers.html

inhalers = (
    name = "Inhalers", 
    model_def = bugsmodel"
    
    # Construct individual response data from contingency table
    for (i in 1 : Ncum[1, 1]) {
        group[i] <- 1
        for (t in 1 : T) { response[i, t] <- pattern[1, t] }
    }
    for (i in (Ncum[1,1] + 1) : Ncum[1, 2]) {
        group[i] <- 2 for (t in 1 : T) { response[i, t] <- pattern[1, t] }
    }

    for (k in 2 : Npattern) {
        for(i in (Ncum[k - 1, 2] + 1) : Ncum[k, 1]) {
            group[i] <- 1 for (t in 1 : T) { response[i, t] <- pattern[k, t] }
        }
        for(i in (Ncum[k, 1] + 1) : Ncum[k, 2]) {
            group[i] <- 2 for (t in 1 : T) { response[i, t] <- pattern[k, t] }
        }
    }

    # Model
    for (i in 1 : N) {
        for (t in 1 : T) {
            for (j in 1 : Ncut) {
                # Cumulative probability of worse response than j
                logit(Q[i, t, j]) <- -(a[j] + mu[group[i], t] + b[i])
            }
            
            # Probability of response = j
            p[i, t, 1] <- 1 - Q[i, t, 1]
            for (j in 2 : Ncut) { p[i, t, j] <- Q[i, t, j - 1] - Q[i, t, j] }
            p[i, t, (Ncut+1)] <- Q[i, t, Ncut]

            response[i, t] ~ dcat(p[i, t, ])
            cumulative.response[i, t] <- cumulative(response[i, t], response[i, t])
        }
        # Subject (random) effects
        b[i] ~ dnorm(0.0, tau)
    }

    # Fixed effects
    for (g in 1 : G) {
        for(t in 1 : T) {
            # logistic mean for group i in period t
            mu[g, t] <- beta * treat[g, t] / 2 + pi * period[g, t] / 2 + kappa * carry[g, t]
        }
    }
    beta ~ dnorm(0, 1.0E-06)
    pi ~ dnorm(0, 1.0E-06)
    kappa ~ dnorm(0, 1.0E-06)

    # ordered cut points for underlying continuous latent variable
    a[1] ~ dflat()T(-1000, a[2])
    a[2] ~ dflat()T(a[1], a[3])
    a[3] ~ dflat()T(a[2], 1000)

    tau ~ dgamma(0.001, 0.001)
    sigma <- sqrt(1 / tau)
    log.sigma <- log(sigma)", 

    data = (
        N = 286, T = 2, G = 2, Npattern = 16, Ncut = 3,
        pattern = row_major_reshape([
            1, 1,
            1, 2,
            1, 3,
            1, 4,
            2, 1,
            2, 2,
            2, 3,
            2, 4,
            3, 1,
            3, 2,
            3, 3,
            3, 4,
            4, 1,
            4, 2,
            4, 3,
            4, 4,
            ], (16, 2)),
        Ncum = row_major_reshape([
            59, 122,
            157, 170,
            173, 173,
            175, 175,
            186, 226,
            253, 268,
            270, 270,
            271, 271,
            271, 278,
            278, 280,
            280, 281,
            281, 281,
            282, 284,
            285, 285,
            285, 286,
            286, 286], (16, 2)),
        treat = row_major_reshape([
            1, -1, -1, 1], (2, 2)),
        period = row_major_reshape([
            1, -1, 1, -1], (2, 2)),
        carry = row_major_reshape([
            0, -1, 0, 1], (2, 2))
    ),
    
    inits = [
        (beta = 0, pi = 0, kappa = 0, a = [2, 3, 4], tau = 1), 
        (beta = 1, pi = 1, kappa = 0, a = [3, 4, 5], tau = 0.1), 
    ],
)

