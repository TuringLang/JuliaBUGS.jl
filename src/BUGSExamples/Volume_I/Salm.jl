# https://chjackson.github.io/openbugsdoc/Examples/Salm.html

salm = (
    name = "Salm", 
    model_def = bugsmodel"""
        for( i in 1 : doses ) {
            for( j in 1 : plates ) {
                y[i , j] ~ dpois(mu[i , j])
                log(mu[i , j]) <- alpha + beta * log(x[i] + 10) +
                    gamma * x[i] + lambda[i , j]
                lambda[i , j] ~ dnorm(0.0, tau)   
                cumulative.y[i , j] <- cumulative(y[i , j], y[i , j])
            }
        }
        alpha ~ dnorm(0.0,1.0E-6)
        beta ~ dnorm(0.0,1.0E-6)
        gamma ~ dnorm(0.0,1.0E-6)
        tau ~ dgamma(0.001, 0.001)
        sigma <- 1 / sqrt(tau)
        """, 

    data = (
        doses = 6,
        plates = 3,
        y = rreshape([
            15, 21, 29, 16, 18, 21, 16, 26, 33, 27, 41, 60, 33, 38, 41, 20, 27, 42], (6, 3)),
        x = [0, 10, 33, 100, 333, 1000],
    ),
    
    inits = [
        (alpha = 0, beta = 0, gamma = 0, tau = 0.1), 
        (alpha = 1.0, beta = 1.0, gamma = 0.01, tau = 1.0),
    ],
)