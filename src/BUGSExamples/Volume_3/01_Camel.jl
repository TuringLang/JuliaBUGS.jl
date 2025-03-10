name = "Camel: Multivariate normal with structured missing data"

model_def = @bugs begin
    for i in 1:N
        Y[i, 1:2] ~ dmnorm(mu[:], tau[:,:])
    end
    mu[1] = 0
    mu[2] = 0
    tau[1:2, 1:2] ~ dwish(R[:,:], 2)
    R[1, 1] = 0.001
    R[1, 2] = 0
    R[2, 1] = 0
    R[2, 2] = 0.001
    Sigma2[1:2, 1:2] = inverse(tau[:,:])
    rho = Sigma2[1, 2] / sqrt(Sigma2[1, 1] * Sigma2[2, 2])
end

original = """
model
{
    for (i in 1 : N){
        Y[i, 1 : 2] ~ dmnorm(mu[], tau[ , ])
    }
    mu[1] <- 0
    mu[2] <- 0
    tau[1 : 2,1 : 2] ~ dwish(R[ , ], 2)
    R[1, 1] <- 0.001
    R[1, 2] <- 0
    R[2, 1] <- 0;
    R[2, 2] <- 0.001
    Sigma2[1 : 2,1 : 2] <- inverse(tau[ , ])
    rho <- Sigma2[1, 2] / sqrt(Sigma2[1, 1] * Sigma2[2, 2])
}
"""

data = (
    N = 12,
    Y = [
        1 1
        1 -1
        -1 1
        -1 -1
        2 missing
        2 missing
        -2 missing
        -2 missing
        missing 2
        missing 2
        missing -2
        missing -2
    ]
)

inits = (
    tau = [0.1 0; 0 0.1],
    Y = [
        missing missing
        missing missing
        missing missing
        missing missing
        missing 1
        missing 1
        missing 1
        missing 1
        1 missing
        1 missing
        1 missing
        1 missing
    ]
)

inits_alternative = (
    tau = [0.5 0; 0 0.5],
    Y = [
        missing missing
        missing missing
        missing missing
        missing missing
        missing 2
        missing 2
        missing 2
        missing 2
        3 missing
        3 missing
        3 missing
        3 missing
    ]
)

reference_results = (
    var"Sigma2[1, 1]" = (mean = 3.194, std = 2.075),
    var"Sigma2[1, 2]" = (mean = -0.03075, std = 2.465),
    var"Sigma2[2, 1]" = (mean = -0.03075, std = 2.465),
    var"Sigma2[2, 2]" = (mean = 2.32, std = 2.079),
    rho = (mean = -0.00481, std = 0.6591),
    var"tau[1, 1]" = (mean = 0.8616, std = 0.5124),
    var"tau[1, 2]" = (mean = 0.00362, std = 0.7131),
    var"tau[2, 1]" = (mean = 0.00362, std = 0.7131),
    var"tau[2, 2]" = (mean = 0.8616, std = 0.5449)
)

camel = Example(name, model_def, original, data, inits, inits_alternative, reference_results)
