# https://chjackson.github.io/openbugsdoc/Examples/Kidney.html

kidney = (
    missingme="Kidney",
    model_def=@bugs(
        """
for (i in 1 : N) {
    for (j in 1 : M) {
        # Survival times bounded below by censoring times:
        t[i,j] ~ dweib(r, mu[i,j])C(t.cen[i, j], );
        log(mu[i,j ]) <- alpha + beta.age * age[i, j] + beta.sex *sex[i] + beta.dis[disease[i]] + b[i];
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
sigma <- 1 / sqrt(tau); # s.d. of random effects
""",
        false,
        true
    ),
    data=(
        N=38,
        M=2,
        t=[
            8 16
            23 missing
            22 28
            447 318
            30 12
            24 245
            7 9
            511 30
            53 196
            15 154
            7 333
            141 missing
            96 38
            missing missing
            536 missing
            17 missing
            185 177
            292 114
            missing missing
            15 missing
            152 562
            402 missing
            13 66
            39 missing
            12 40
            missing 201
            132 156
            34 30
            2 25
            130 26
            27 58
            missing 43
            152 30
            190 missing
            119 8
            missing missing
            missing 78
            63 missing
        ],
        var"t.cen"=[
            0 0
            0 13
            0 0
            0 0
            0 0
            0 0
            0 0
            0 0
            0 0
            0 0
            0 0
            0 8
            0 0
            149 70
            0 25
            0 4
            0 0
            0 0
            22 159
            0 108
            0 0
            0 24
            0 0
            0 46
            0 0
            113 0
            0 0
            0 0
            0 0
            0 0
            0 0
            5 0
            0 0
            0 5
            0 0
            54 16
            6 0
            0 8
        ],
        age=[
            28 28
            48 48
            32 32
            31 32
            10 10
            16 17
            51 51
            55 56
            69 69
            51 52
            44 44
            34 34
            35 35
            42 42
            17 17
            60 60
            60 60
            43 44
            53 53
            44 44
            46 47
            30 30
            62 63
            42 43
            43 43
            57 58
            10 10
            52 52
            53 53
            54 54
            56 56
            50 51
            57 57
            44 45
            22 22
            42 42
            52 52
            60 60
        ],
        var"beta.dis"=[0, missing, missing, missing],
        sex=[
            0,
            1,
            0,
            1,
            0,
            1,
            0,
            1,
            1,
            0,
            1,
            1,
            1,
            1,
            1,
            0,
            1,
            1,
            1,
            1,
            0,
            1,
            1,
            1,
            0,
            1,
            1,
            1,
            0,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            0,
        ],
        disease=[
            1,
            2,
            1,
            1,
            1,
            1,
            2,
            2,
            3,
            2,
            3,
            1,
            3,
            3,
            1,
            3,
            1,
            1,
            2,
            1,
            4,
            1,
            3,
            3,
            3,
            3,
            2,
            3,
            2,
            2,
            3,
            3,
            4,
            2,
            1,
            1,
            4,
            4,
        ],
    ),
    inits=[
        (
            var"beta.age"=0,
            var"beta.sex"=0,
            var"beta.dis"=[missing, 0, 0, 0],
            alpha=0,
            r=1,
            tau=0.3,
        ),
        (
            var"beta.age"=-1,
            var"beta.sex"=1,
            var"beta.dis"=[missing, 1, 1, 1],
            alpha=1,
            r=1.5,
            tau=1,
        ),
    ],
)
