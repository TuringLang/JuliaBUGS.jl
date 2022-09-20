# https://chjackson.github.io/openbugsdoc/Examples/Equiv.html

equiv = (
    name = "Equiv", 
    model_def = bugsmodel"""
        for( k in 1 : P ) {
            for( i in 1 : N ) {
                Y[i , k] ~ dnorm(m[i , k], tau1)
                m[i , k] <- mu + sign[T[i , k]] * phi / 2 + sign[k] * pi / 2 + delta[i]
                T[i , k] <- group[i] * (k - 1.5) + 1.5
            }
        }
        for( i in 1 : N ) {
            delta[i] ~ dnorm(0.0, tau2)
        }
        tau1 ~ dgamma(0.001, 0.001) 
        sigma1 <- 1 / sqrt(tau1)
        tau2 ~ dgamma(0.001, 0.001) 
        sigma2 <- 1 / sqrt(tau2)
        mu ~ dnorm(0.0, 1.0E-6)
        phi ~ dnorm(0.0, 1.0E-6)
        pi ~ dnorm(0.0, 1.0E-6)
        theta <- exp(phi)
        equiv <- step(theta - 0.8) - step(theta - 1.2)
        """, 

    data = (
        N = 10,
        P = 2,
        group = [1, 1, -1, -1, -1, 1, 1, 1, -1, -1],
        Y = row_major_reshape([
            1.40, 1.65,
            1.64, 1.57,
            1.44, 1.58,
            1.36, 1.68,
            1.65, 1.69,
            1.08, 1.31,
            1.09, 1.43,
            1.25, 1.44,
            1.25, 1.39,
            1.30, 1.52
        ], (10, 2)),
        sign = [1, -1],
    ),
    
    inits = [
        (mu = 0, phi = 0, pi = 0, tau1 = 1, tau2 = 1), 
        (mu = 10, phi = 10, pi = 10, tau1 = 0.1, tau2 = 0.1), 
    ],
)