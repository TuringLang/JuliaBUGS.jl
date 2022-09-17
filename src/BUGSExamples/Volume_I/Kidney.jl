# https://chjackson.github.io/openbugsdoc/Examples/Kidney.html

kidney = (
    name = "Kidney", 
    model_def = bugsmodel"
    for (i in 1 : N) {
        for (j in 1 : M) {
            # Survival times bounded below by censoring times:
            t[i,j] ~ dweib(r, mu[i,j])C(t.cen[i, j], );
            log(mu[i,j ]) <- alpha + beta.age * age[i, j]
                + beta.sex *sex[i]
                + beta.dis[disease[i]] + b[i];
            cumulative.t[i,j] <- cumulative(t[i,j], t[i,j])
        }
        # Random effects:
        b[i] ~ dnorm(0.0, tau)
    }
    
    # Priors:
    alpha ~ dnorm(0.0, 0.0001);
    beta.age ~ dnorm(0.0, 0.0001);
    beta.sex ~ dnorm(0.0, 0.0001);
    # beta.dis[1] <- 0; # corner-point constraint
    for(k in 2 : 4) {
        beta.dis[k] ~ dnorm(0.0, 0.0001);
    }
    tau ~ dgamma(1.0E-3, 1.0E-3);
    r ~ dgamma(1.0, 1.0E-3);
    sigma <- 1 / sqrt(tau); # s.d. of random effects", 

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


