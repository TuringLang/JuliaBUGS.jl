name = "Fun Shapes: Square minus Circle"

model_def = @bugs begin
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O = 1
    O ~ dbern(constraint)
    constraint = step(x * x + y * y - 1)
end

original = """
model
{
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O <- 1
    O ~ dbern(constraint)
    constraint <- step(x * x + y * y - 1)
}
"""

data = NamedTuple()

inits = (
    x = 0.99,
    y = 0.99
)

square_minus_circle = Example(
    name,
    model_def,
    original,
    data,
    inits,
    inits,
    NamedTuple()
)
