# Special Cases in the BUGS Language

Here we record some of the special cases in the BUGS language in the original BUGS softwares, JuliaBUGS may or may not inherent these behaviors.

## Nested Indexing on the Left-Hand Side

```julia
model_def = @bugs x[y[1]] ~ dnorm(0, 1) # this is permitted
data = (y=[1,2,3],)
```

## Function Application on the Left-Hand Side Index is Not Permitted

This is identified during the compilation phase, not during parsing.

## The arguments to the distributions functions must be "simple": they are either a variable or a constant, their should be no function application other than the arithmetic operators

```R
model {
 x ~ dnorm(y[1] + 1, 1)
} # fail at parsing

model {
 x ~ dnorm(sum(y[1:2]), 1)
} # fail at parsing

model {
 x ~ dnorm(y[sum(y[1:2])], 1)
} # pass the parser, but fail at compile

model {
 x ~ dnorm(y[y[2]], 1)
} # this is okay

model {
  x ~ dnorm(y[y[2]+1], 1)
} # this is also okay

list(y = c(1, 2, 3))
```

The reason behind this is two fold: (1) forcing the user to use `~` to identify the dependency between random variables, instead of expressions, (2) make implementation of automatic differentiation easier.

## Indexing with Transformed Variables is Not Permitted

This restriction is due to the current compiler implementation.

```julia
model{
 a <- max(y[2], y[3])
 x[a + 1] ~ dnorm(0, 1)
}

list(y=c(1, 2, 3))
```

The reason for this is that the transformed variable and indices are evaluated simultaneously, and the transformed variable is not available at the time of indexing. This is a limitation of the current implementation.
