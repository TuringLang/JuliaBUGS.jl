# https://chjackson.github.io/openbugsdoc/Examples/Stacks.html

stacks = (
    name = "Stacks", 
    model_def = bugsmodel"""
        # Standardise x's and coefficients
        for (j in 1 : p) {
            b[j] <- beta[j] / sd(x[ , j ])
            for (i in 1 : N) {
                z[i, j] <- (x[i, j] - mean(x[, j])) / sd(x[ , j])
            }
        }
        b0 <- beta0 - b[1] * mean(x[, 1]) - b[2] * mean(x[, 2]) - b[3] * mean(x[, 3])

        # Model
        d <- 4; # degrees of freedom for t
        for (i in 1 : N) {
            Y[i] ~ dnorm(mu[i], tau)
            # Y[i] ~ ddexp(mu[i], tau)
            # Y[i] ~ dt(mu[i], tau, d)

            mu[i] <- beta0 + beta[1] * z[i, 1] + beta[2] * z[i, 2] + beta[3] * z[i, 3]
            stres[i] <- (Y[i] - mu[i]) / sigma
            outlier[i] <- step(stres[i] - 2.5) + step(-(stres[i] + 2.5) )
        }
        
        # Priors
        beta0 ~ dnorm(0, 0.00001)
        for (j in 1 : p) {
            beta[j] ~ dnorm(0, 0.00001)    # coeffs independent
            # beta[j] ~ dnorm(0, phi) # coeffs exchangeable (ridge regression)
        }
        tau ~ dgamma(1.0E-3, 1.0E-3)
        phi ~ dgamma(1.0E-2,1.0E-2)
        # standard deviation of error distribution
        sigma <- sqrt(1 / tau) # normal errors
        # sigma <- sqrt(2) / tau # double exponential errors
        # sigma <- sqrt(d / (tau * (d - 2))); # t errors on d degrees of freedom
        """, 

    data = (
        p = 3, N = 21,
        Y = [42, 37, 37, 28, 18, 18, 19, 20, 15, 14, 14, 13, 11, 12, 8, 7, 8, 8, 9, 15, 15],
        x = rreshape([
            80, 27, 89,
            80, 27, 88,
            75, 25, 90,
            62, 24, 87,
            62, 22, 87,
            62, 23, 87,
            62, 24, 93,
            62, 24, 93,
            58, 23, 87,
            58, 18, 80,
            58, 18, 89,
            58, 17, 88,
            58, 18, 82,
            58, 19, 93,
            50, 18, 89,
            50, 18, 86,
            50, 19, 72,
            50, 19, 79,
            50, 20, 80,
            56, 20, 82,
            70, 20, 91
            ], (21, 3))
    ),
    
    inits = [
        (beta0 = 10, beta=[0,0, 0], tau = 0.1, phi = 0.1), 
        (beta0 = 1.0, beta=[1.0,1.0, 1.0], tau = 1.0, phi = 1.0), 
    ],
)
