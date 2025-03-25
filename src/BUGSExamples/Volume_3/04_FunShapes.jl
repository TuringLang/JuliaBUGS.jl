name = "Fun Shapes: general constraints"

# Circle model
circle_model_def = @bugs begin
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O = 0
    O ~ dbern(constraint)
    constraint = step(x * x + y * y - 1)
end

# Square minus circle model
square_minus_circle_model_def = @bugs begin
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O = 1
    O ~ dbern(constraint)
    constraint = step(x * x + y * y - 1)
end

# Ring model
ring_model_def = @bugs begin
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O1 = 0
    O1 ~ dbern(constraint1)
    constraint1 = step(x * x + y * y - 1)
    O2 = 1
    O2 ~ dbern(constraint2)
    constraint2 = step(x * x + y * y - 0.25)
end

# Hollow square model
hollow_square_model_def = @bugs begin
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O = 0
    O ~ dbern(constraint)
    constraint = (step(0.5 - abs(x)) * step(0.50 - abs(y)))
end

# Parallelogram model
parallelogram_model_def = @bugs begin
    x ~ dunif(0, 1)
    y ~ dunif(-1, 1.0)
    O1 = 1
    O1 ~ dbern(constraint1)
    constraint1 = step(x + y)
    O2 = 0
    O2 ~ dbern(constraint2)
    constraint2 = step(x + y - 1)
end

original_circle = """
model
{
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O <- 0
    O ~ dbern(constraint)
    constraint <- step(x * x + y * y - 1)
}
"""

original_square_minus_circle = """
model
{
    x ~ dunif(-1, 1)
    y ~ dunif(-1, 1)
    O <- 1
    O ~ dbern(constraint)
    constraint <- step(x * x + y * y - 1)
}
"""

original_ring = """
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

original_hollow_square = """
model
{
   x ~ dunif(-1, 1)
   y ~ dunif(-1, 1)
   O <- 0
   O ~ dbern(constraint)
   constraint <- (step(0.5 - abs(x)) * step(0.50 - abs(y)))
}
"""

original_parallelogram = """
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

# Combined original for the Example structure
original = original_circle

# No data needed for these examples
data = ()

# Initial values for each model
circle_inits = (
    x = 0.0,
    y = 0.0
)

square_minus_circle_inits = (
    x = 0.99,
    y = 0.99
)

ring_inits = (
    x = 0.6,
    y = 0.6
)

hollow_square_inits = (
    x = 0.75,
    y = 0.75
)

parallelogram_inits = (
    x = 0.5,
    y = 0.0
)

# Additional Example objects for each shape
circle = Example(
    "Fun Shapes: Circle",
    circle_model_def,
    original_circle,
    data,
    circle_inits,
    circle_inits,
    NamedTuple()
)

square_minus_circle = Example(
    "Fun Shapes: Square minus circle",
    square_minus_circle_model_def,
    original_square_minus_circle,
    data,
    square_minus_circle_inits,
    square_minus_circle_inits,
    NamedTuple()
)

ring = Example(
    "Fun Shapes: Ring",
    ring_model_def,
    original_ring,
    data,
    ring_inits,
    ring_inits,
    NamedTuple()
)

hollow_square = Example(
    "Fun Shapes: Hollow square",
    hollow_square_model_def,
    original_hollow_square,
    data,
    hollow_square_inits,
    hollow_square_inits,
    NamedTuple()
)

parallelogram = Example(
    "Fun Shapes: Parallelogram",
    parallelogram_model_def,
    original_parallelogram,
    data,
    parallelogram_inits,
    parallelogram_inits,
    NamedTuple()
)
