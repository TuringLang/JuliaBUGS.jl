# # Pumps: Conjugate Gamma-Poisson Hierarchical Model
#
# This example concerns the number of failures of pumps in a nuclear
# power plant, and uses a conjugate gamma-Poisson hierarchical model.
#
# ## DoodleBUGS Model
#
# ```@raw html
# <doodle-bugs width="100%" height="600px" model="pumps"></doodle-bugs>
# ```
#
# ## Original BUGS Syntax

original_syntax_program = """
model{
    for (i in 1 : N) {
        theta[i] ~ dgamma(alpha, beta)
        lambda[i] <- theta[i] * t[i]
        x[i] ~ dpois(lambda[i])
    }
    alpha ~ dexp(1)
    beta ~ dgamma(0.1, 1.0)
}
"""

# ## `@bugs` Macro Syntax

model_def = """
@bugs begin
    for i in 1:N
        theta[i] ~ dgamma(alpha, beta)
        lambda[i] = theta[i] * t[i]
        x[i] ~ dpois(lambda[i])
    end
    alpha ~ dexp(1)
    beta ~ dgamma(0.1, 1.0)
end
"""

# ## `@model` Macro Syntax

model_function = ""

# Data is loaded from `data.json` in the source directory.

_pumps_data = load_example_data(joinpath(@__DIR__, "data.json"))

pumps = BUGSExample(;
    name = "Pumps: conjugate gamma-Poisson hierarchical model",
    original_syntax_program = original_syntax_program,
    model_def = model_def,
    model_function = model_function,
    data = _pumps_data.data,
    inits = _pumps_data.inits,
    inits_alternative = _pumps_data.inits_alternative,
    reference_results = _pumps_data.reference_results,
)
