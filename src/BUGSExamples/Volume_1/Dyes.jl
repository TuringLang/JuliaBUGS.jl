# https://chjackson.github.io/openbugsdoc/Examples/Dyes.html

dyes = (
    name="Dyes",
    model_def=@bugs(
        """
for(i in 1 : batches) {
    mu[i] ~ dnorm(theta, tau.btw)
    for(j in 1 : samples) {
        y[i , j] ~ dnorm(mu[i], tau.with)
        cumulative.y[i , j] <- cumulative(y[i , j], y[i , j])
    }
}   
sigma2.with <- 1 / tau.with
sigma2.btw <- 1 / tau.btw
tau.with ~ dgamma(0.001, 0.001)
tau.btw ~ dgamma(0.001, 0.001)
theta ~ dnorm(0.0, 1.0E-10)
""",
        false,
        true
    ),
    data=(
        batches=6,
        samples=5,
        Y=[
            1545 1440 1440 1520 1580
            1540 1555 1490 1560 1495
            1595 1550 1605 1510 1560
            1445 1440 1595 1465 1545
            1595 1630 1515 1635 1625
            1520 1455 1450 1480 1445
        ],
    ),
    inits=[
        (theta=1500, var"tau.with"=1, var"tau.btw"=1),
        (theta=3000, var"tau.with"=0.1, var"tau.btw"=0.1),
    ],
)
