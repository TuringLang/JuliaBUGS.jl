name = "Dyes"

model_def = @bugs begin
    for i in 1:batches
        mu[i] ~ dnorm(theta, var"tau.btw")
        for j in 1:samples
            y[i, j] ~ dnorm(mu[i], var"tau.with")
            var"cumulative.y"[i, j] = cumulative(y[i, j], y[i, j])
        end
    end
    var"sigma2.with" = 1 / var"tau.with"
    var"sigma2.btw" = 1 / var"tau.btw"
    var"tau.with" ~ dgamma(0.001, 0.001)
    var"tau.btw" ~ dgamma(0.001, 0.001)
    theta ~ dnorm(0.0, 1.0e-10)
end

data = (
    batches = 6,
    samples = 5,
    Y = [1545 1440 1440 1520 1580
         1540 1555 1490 1560 1495
         1595 1550 1605 1510 1560
         1445 1440 1595 1465 1545
         1595 1630 1515 1635 1625
         1520 1455 1450 1480 1445]
)

inits = (
    theta = 1500,
    var"tau.with" = 1,
    var"tau.btw" = 1
)
inits_alternative = (
    theta = 3000,
    var"tau.with" = 0.1,
    var"tau.btw" = 0.1
)

reference_results = nothing

dyes = Example(name, model_def, data, inits, inits_alternative, reference_results)
