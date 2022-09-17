# https://chjackson.github.io/openbugsdoc/Examples/Mice.html

mice = (
    name = "Mice", 
    model_def = bugsmodel"
        for(i in 1 : M) {
            for(j in 1 : N) {
                t[i, j] ~ dweib(r, mu[i])C(t.cen[i, j],)
                cumulative.t[i, j] <- cumulative(t[i, j], t[i, j])
            }
            mu[i] <- exp(beta[i])
            beta[i] ~ dnorm(0.0, 0.001)
            median[i] <- pow(log(2) * exp(-beta[i]), 1/r)
        }
        r ~ dexp(0.001)
        veh.control <- beta[2] - beta[1]
        test.sub <- beta[3] - beta[1]
        pos.control <- beta[4] - beta[1]", 

    data = (
        t = row_major_reshape([
            12, 1, 21, 25, 11, 26, 27, 30, 13, 12, 21, 20, 23, 25, 23, 29, 35, missing, 31, 36,
            32, 27, 23, 12, 18, missing, missing, 38, 29, 30, missing, 32, missing, missing, missing, missing, 25, 30, 37, 27,
            22, 26, missing, 28, 19, 15, 12, 35, 35, 10, 22, 18, missing, 12, missing, missing, 31, 24, 37, 29,
            27, 18, 22, 13, 18, 29, 28, missing, 16, 22, 26, 19, missing, missing, 17, 28, 26, 12, 17, 26
            ],(4, 20)),
        var"t.cen" = row_major_reshape([
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 0, 0,
            0, 0, 0, 0, 0, 40, 40, 0, 0, 0, 40, 0, 40, 40, 40, 40, 0, 0, 0, 0,
            0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 24, 0, 40, 40, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 20, 0, 0, 0, 0, 29, 10, 0, 0, 0, 0, 0, 0
            ], (4, 20)),
        M = 4, N = 20
    ),
    
    inits = [
        (beta = [-1, -1, -1, -1], r = 1), 
        (beta = [0.0, 0.0, 0.0, 0.0], r = 2), 
    ],
)





