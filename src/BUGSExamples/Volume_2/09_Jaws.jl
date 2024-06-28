name = "Jaws: repeated measures analysis of variance"

model_def = @bugs begin
    beta0 ~ dnorm(0.0, 0.001)
    beta1 ~ dnorm(0.0, 0.001)
    for i in 1:N
        Y[i, 1:M] ~ dmnorm(mu[:], Omega[:, :])
    end
    for j in 1:M
        mu[j] = beta0 + beta1 * age[j]
    end
    Omega[1:M, 1:M] ~ dwish(R[:, :], 4)
    Sigma[1:M, 1:M] = inverse(Omega[:, :])
end

original = """
model
{
    beta0 ~ dnorm(0.0, 0.001)
    beta1 ~ dnorm(0.0, 0.001)
    for (i in 1:N) {
        Y[i, 1:M] ~ dmnorm(mu[], Omega[ , ])
    }
    for(j in 1:M) {
        mu[j] <- beta0 + beta1* age[j]
    }
    Omega[1 : M , 1 : M] ~ dwish(R[ , ], 4)
    Sigma[1 : M , 1 : M] <- inverse(Omega[ , ])
}
"""

data = (M = 4, N = 20,
    Y =
    [47.8 48.8 49.0 49.7
     46.4 47.3 47.7 48.4
     46.3 46.8 47.8 48.5
     45.1 45.3 46.1 47.2
     47.6 48.5 48.9 49.3
     52.5 53.2 53.3 53.7
     51.2 53.0 54.3 54.5
     49.8 50.0 50.3 52.7
     48.1 50.8 52.3 54.4
     45.0 47.0 47.3 48.3
     51.2 51.4 51.6 51.9
     48.5 49.2 53.0 55.5
     52.1 52.8 53.7 55.0
     48.2 48.9 49.3 49.8
     49.6 50.4 51.2 51.8
     50.7 51.7 52.7 53.3
     47.2 47.7 48.4 49.5
     53.3 54.6 55.1 55.3
     46.2 47.5 48.1 48.4
     46.3 47.6 51.3 51.8],
    age = [8.0, 8.5, 9.0, 9.5],
    R = [1 0 0 0
         0 1 0 0
         0 0 1 0
         0 0 0 1])

inits = (beta0 = 40, beta1 = 1)
inits_alternative = (beta0 = 10, beta1 = 10)

reference_results = (
    beta0 = (mean = 33.52, std = 33.57), beta1 = (mean = 1.889, std = 1.882),
    var"mu[1]" = (mean = 48.63, std = 48.64), var"mu[2]" = (mean = 49.58, std = 49.58),
    var"mu[3]" = (mean = 50.52, std = 50.52), var"mu[4]" = (mean = 51.48, std = 51.48))

jaws = Example(name, model_def, original, data, inits, inits_alternative, reference_results)
