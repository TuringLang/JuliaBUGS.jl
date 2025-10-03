name = "Fun Shapes: Circle"

model_def = @bugs begin
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O = 0
    O ~ dbern(constraint)
    constraint = step(x * x + y * y - 1)
end

original = """
model
{
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O <- 0
    O ~ dbern(constraint)
    constraint <- step(x * x + y * y - 1)
}
"""

data = NamedTuple()

inits = (
    x = 0.0,
    y = 0.0
)

circle = Example(
    name,
    model_def,
    original,
    data,
    inits,
    inits,
    NamedTuple()
)
