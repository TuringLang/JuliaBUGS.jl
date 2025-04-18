N <-
    42
NT <-
    17
eps <- 0.00001
obs.t <-
    c(
        1, 1, 2, 2, 3, 4, 4, 5, 5, 8, 8, 8, 8, 11, 11, 12, 12, 15,
        17, 22, 23, 6, 6, 6, 6, 7, 9, 10, 10, 11, 13, 16, 17, 19, 20,
        22, 23, 25, 32, 32, 34, 35
    )
fail <-
    c(
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0,
        0
    )
Z <-
    c(
        0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
        0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, -0.5, -0.5, -0.5,
        -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5,
        -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5
    )
t <-
    c(
        1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 22, 23,
        35
    )
Npairs <-
    21
pair <-
    c(
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        19, 18, 8, 1, 20, 6, 2, 10, 3, 14, 4, 11, 7, 9, 12, 16, 17, 5, 13, 15, 21
    )


# Initialize Y and dN matrices
Y <- matrix(0, nrow = N, ncol = NT)
dN <- matrix(0, nrow = N, ncol = NT)

# Compute Y and dN
for (i in 1:N) {
    for (j in 1:NT) {
        # risk set = 1 if obs.t >= t
        Y[i, j] <- as.numeric(obs.t[i] - t[j] + eps >= 0)

        # counting process jump = 1 if obs.t in [t[j], t[j+1])
        # i.e. if t[j] <= obs.t < t[j+1]
        dN[i, j] <- Y[i, j] * as.numeric(t[j + 1] - obs.t[i] - eps >= 0) * fail[i]
    }
}
