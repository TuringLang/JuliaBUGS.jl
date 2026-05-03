# # Rats: A Normal Hierarchical Model
#
# This example is taken from section 6 of Gelfand et al. (1990), and concerns
# 30 young rats whose weights were measured weekly for five weeks.
#
# ## DoodleBUGS Model
#
# ```@raw html
# <doodle-bugs width="100%" height="600px" model="rats"></doodle-bugs>
# ```
#
# ## Original BUGS Syntax

original_syntax_program = """
model{
    for(i in 1:N) {
        for(j in 1:T) {
            Y[i, j] ~ dnorm(mu[i, j], tau.c)
            mu[i, j] <- alpha[i] + beta[i] * (x[j] - xbar)
        }
        alpha[i] ~ dnorm(alpha.c, alpha.tau)
        beta[i] ~ dnorm(beta.c, beta.tau)
    }
    tau.c ~ dgamma(0.001, 0.001)
    sigma <- 1 / sqrt(tau.c)
    alpha.c ~ dnorm(0.0, 1.0E-6)
    alpha.tau ~ dgamma(0.001, 0.001)
    beta.c ~ dnorm(0.0, 1.0E-6)
    beta.tau ~ dgamma(0.001, 0.001)
    alpha0 <- alpha.c - xbar * beta.c
}
"""

# ## `@bugs` Macro Syntax

model_def = """
@bugs begin
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(mu[i, j], var"tau.c")
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ dnorm(var"beta.c", var"beta.tau")
    end
    var"tau.c" ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(var"tau.c")
    var"alpha.c" ~ dnorm(0.0, 1.0e-6)
    var"alpha.tau" ~ dgamma(0.001, 0.001)
    var"beta.c" ~ dnorm(0.0, 1.0e-6)
    var"beta.tau" ~ dgamma(0.001, 0.001)
    alpha0 = var"alpha.c" - xbar * var"beta.c"
end
"""

# ## `@model` Macro Syntax

model_function = """
@model function rats(
    (; alpha, beta, var"tau.c", var"alpha.c", var"alpha.tau", var"beta.c", var"beta.tau"),
    N, T, x, xbar, Y
)
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(mu[i, j], var"tau.c")
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ dnorm(var"beta.c", var"beta.tau")
    end
    var"tau.c" ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(var"tau.c")
    var"alpha.c" ~ dnorm(0.0, 1.0e-6)
    var"alpha.tau" ~ dgamma(0.001, 0.001)
    var"beta.c" ~ dnorm(0.0, 1.0e-6)
    var"beta.tau" ~ dgamma(0.001, 0.001)
    alpha0 = var"alpha.c" - xbar * var"beta.c"
end
"""

# ## Reference Results
#
# | Parameter | Mean  | Std    |
# |-----------|-------|--------|
# | alpha0    | 106.6 | 3.66   |
# | beta.c    | 6.186 | 0.1086 |
# | sigma     | 6.093 | 0.4643 |
#
# Data is loaded from `data.json` in the source directory.

_rats_data = load_example_data(joinpath(@__DIR__, "data.json"))

rats = BUGSExample(;
    name = "Rats: a normal hierarchical model",
    original_syntax_program = original_syntax_program,
    model_def = model_def,
    model_function = model_function,
    data = _rats_data.data,
    inits = _rats_data.inits,
    inits_alternative = _rats_data.inits_alternative,
    reference_results = _rats_data.reference_results,
)
