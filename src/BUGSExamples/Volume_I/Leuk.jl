# https://chjackson.github.io/openbugsdoc/Examples/Leuk.html

leuk = (
    name="Leuk",
    model_def=bugsmodel"""
      # Set up data
      for(i in 1:N) {
          for(j in 1:T) {
              # risk set = 1 if obs.t >= t
              Y[i,j] <- step(obs.t[i] - t[j] + eps)
              # counting process jump = 1 if obs.t in [ t[j], t[j+1] )
              # i.e. if t[j] <= obs.t < t[j+1]
              dN[i, j] <- Y[i, j] * step(t[j + 1] - obs.t[i] - eps) * fail[i]
          }
      }

      # Model
      for(j in 1:T) {
          for(i in 1:N) {
              dN[i, j] ~ dpois(Idt[i, j]) # Likelihood
              Idt[i, j] <- Y[i, j] * exp(beta * Z[i]) * dL0[j]    # Intensity
          }
          dL0[j] ~ dgamma(mu[j], c)
          mu[j] <- dL0.star[j] * c # prior mean hazard

          # Survivor function = exp(-Integral{l0(u)du})^exp(beta*z)
          S.treat[j] <- pow(exp(-sum(dL0[1 : j])), exp(beta * -0.5));
          S.placebo[j] <- pow(exp(-sum(dL0[1 : j])), exp(beta * 0.5));   
      }

      c <- 0.001
      r <- 0.1
      for (j in 1 : T) {
          dL0.star[j] <- r * (t[j + 1] - t[j])
      }
      beta ~ dnorm(0.0,0.000001)
      """,
    data=(
        N=42,
        T=17,
        eps=1.0E-10,
        var"obs.t"=[
            1,
            1,
            2,
            2,
            3,
            4,
            4,
            5,
            5,
            8,
            8,
            8,
            8,
            11,
            11,
            12,
            12,
            15,
            17,
            22,
            23,
            6,
            6,
            6,
            6,
            7,
            9,
            10,
            10,
            11,
            13,
            16,
            17,
            19,
            20,
            22,
            23,
            25,
            32,
            32,
            34,
            35,
        ],
        fail=[
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            0,
            1,
            0,
            1,
            0,
            0,
            1,
            1,
            0,
            0,
            0,
            1,
            1,
            0,
            0,
            0,
            0,
            0,
        ],
        Z=[
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
            -0.5,
        ],
        t=[1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 22, 23, 35],
    ),
    inits=[
        (
            beta=0.0,
            dL0=[
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
            ],
        ),
        (
            beta=1.0,
            dL0=[
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
                2.0,
            ],
        ),
    ],
)
