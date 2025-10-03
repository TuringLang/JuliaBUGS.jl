name = "Fun Shapes: Hollow Square"

model_def = @bugs begin
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O = 0
    O ~ dbern(constraint)
    constraint = (step(0.5 - abs(x)) * step(0.50 - abs(y)))
end

original = """
model
{
   x ~ dunif(-1, 1)
   y ~ dunif(-1, 1)
   O <- 0
   O ~ dbern(constraint)
   constraint <- (step(0.5 - abs(x)) * step(0.50 - abs(y)))
}
"""

data = NamedTuple()

inits = (
    x = 0.75,
    y = 0.75
)

hollow_square = Example(
    name,
    model_def,
    original,
    data,
    inits,
    inits,
    NamedTuple()
)
