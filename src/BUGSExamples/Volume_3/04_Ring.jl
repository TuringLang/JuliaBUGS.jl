name = "Fun Shapes: Ring"

model_def = @bugs begin
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O1 = 0
    O1 ~ dbern(constraint1)
    constraint1 = step(x * x + y * y - 1)
    O2 = 1
    O2 ~ dbern(constraint2)
    constraint2 = step(x * x + y * y - 0.25)
end

original = """
model
{
   x ~ dunif(-1, 1)
   y ~ dunif(-1, 1)
   O1 <- 0
   O1 ~ dbern(constraint1)
   constraint1 <- step(x * x + y * y - 1)   
   O2 <- 1
   O2 ~ dbern(constraint2)
   constraint2 <- step( x * x + y * y - 0.25)
}
"""

data = NamedTuple()

inits = (
    x = 0.6,
    y = 0.6
)

ring = Example(
    name,
    model_def,
    original,
    data,
    inits,
    inits,
    NamedTuple()
)
