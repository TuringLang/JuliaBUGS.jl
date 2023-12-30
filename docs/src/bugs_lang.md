# Special Cases in the BUGS Language

## Nested Indexing on the Left-Hand Side
```julia
model_def = @bugs x[y[1]] ~ dnorm(0, 1) # this is permitted
data = (y=[1,2,3],)
```

## Function Application on the Left-Hand Side Index is Not Permitted - 
This is identified during the compilation phase, not during parsing.


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
