# https://chjackson.github.io/openbugsdoc/Examples/Pumps.html

pumps = (
    name = "Pumps", 
    model_def = bugsmodel"
        for (i in 1 : N) {
        theta[i] ~ dgamma(alpha, beta)
        lambda[i] <- theta[i] * t[i]
        x[i] ~ dpois(lambda[i])
        }

        alpha ~ dexp(1)
        beta ~ dgamma(0.1, 1.0)", 

    data = (
        t = [94.3, 15.7, 62.9, 126, 5.24, 31.4, 1.05, 1.05, 2.1, 10.5],
        x = [5, 1, 5, 14, 3, 19, 1, 1, 4, 22],
        N = 10,
    ),

    inits = [
        (alpha = 1, beta = 1), 
        (alpha = 10, beta = 10), 
    ],
)
