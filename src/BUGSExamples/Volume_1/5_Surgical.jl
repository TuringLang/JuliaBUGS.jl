# https://chjackson.github.io/openbugsdoc/Examples/Surgical.html

surgical_simple = (
    name="Surgical",
    model_def=@bugs(
        """
for( i in 1 : N ) {
    p[i] ~ dbeta(1.0, 1.0)
    r[i] ~ dbin(p[i], n[i])
}
""",
        false,
        true
    ),
    data=(
        n=[47, 148, 119, 810, 211, 196, 148, 215, 207, 97, 256, 360],
        r=[0, 18, 8, 46, 8, 13, 9, 31, 14, 8, 29, 24],
        N=12,
    ),
    inits=[
        (p=[0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1],),
        (p=[0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],),
    ],
)

surgical_realistic = (
    name="Surgical",
    model_def=@bugs(
        """
for( i in 1 : N ) {
    b[i] ~ dnorm(mu,tau)
    r[i] ~ dbin(p[i],n[i])
    logit(p[i]) <- b[i]
}
pop.mean <- exp(mu) / (1 + exp(mu))
mu ~ dnorm(0.0,1.0E-6)
sigma <- 1 / sqrt(tau)
tau ~ dgamma(0.001,0.001)
""",
        false,
        true
    ),
    data=(
        n=[47, 148, 119, 810, 211, 196, 148, 215, 207, 97, 256, 360],
        r=[0, 18, 8, 46, 8, 13, 9, 31, 14, 8, 29, 24],
        N=12,
    ),
    inits=[
        (b=[0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1], tau=1, mu=0),
        (b=[0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], tau=0.1, mu=1.0),
    ],
)
