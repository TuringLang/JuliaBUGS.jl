name = "Fun Shapes: Parallelogram"

model_def = @bugs begin
    x ~ dunif(0, 1)
    y ~ dunif(-1, 1.0)
    O1 = 1
    O1 ~ dbern(constraint1)
    constraint1 = step(x + y)
    O2 = 0
    O2 ~ dbern(constraint2)
    constraint2 = step(x + y - 1)
end

original = """
model
{
   x ~ dunif(0, 1)
   y ~ dunif(-1, 1.0)
   O1 <- 1
   O1 ~ dbern(constraint1)
   constraint1 <- step(x + y)
   O2 <- 0
   O2 ~ dbern(constraint2)   
   constraint2 <- step(x + y - 1)
}
"""

data = NamedTuple()

inits = (
    x = 0.5,
    y = 0.0
)

parallelogram = Example(
    name,
    model_def,
    original,
    data,
    inits,
    inits,
    NamedTuple()
)
