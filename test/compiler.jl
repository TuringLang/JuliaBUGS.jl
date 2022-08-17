## tests for analyze_data!
data = Dict(
    :N => 2,
    :b => 3,
    :g => [1, 2, 3]
)

compiler_state = CompilerState()
parsedata!(data, compiler_state)
@show compiler_state;
##

# test for resolve
resolve(:n, rules, arrays)
resolve(10, rules, arrays)
resolve(Meta.parse("g[2]"), rules, arrays)

## tests for unroll
expr = bugsmodel"""      
### Likelihood
    # dummy assignment for easy understanding
    variable.0 <- 1

    # nested loop
    for (i in 1:3) {
        # constant assignment
        array.variable.0[i] <- 1
        # assignment using loop variable
        array.variable.1[i] <- i + 1
        
        # nested loops in another for loop
        for (j in 1:2) {
            # loop bound depend on loop variable
            for (k in 1:j) {
                array.variable.2[i, j, k] = 2
            }
        }
    }

    # variable loop bound that can be resolve from user input
    for (i in 1:N) {
        array.variable.3[i] <- i
    }

    for (i in 1:g[2]) {
        array.variable.4[i] <- i
    }

    # dummy assignment for easy understanding
    variable.1 <- 1
"""
unrollforloops!(expr, compiler_state)
expr

## Tests for unrolling: corner case
expr = bugsmodel"""      
    for (i in 1:N) {
        n[i] = i
        for(j in 1:n[i]) {
            m[i, j] = i + j
        }
    }     
"""
unrollforloops!(expr, compiler_state)
parse_logical_assignments!(expr, compiler_state)
@show expr
@show compiler_state

## tests for parse_logical_assignments!
expr = bugsmodel"""
    v[2] <- h[3] + (g[2] * d) * c
    w[6] <- f[2] / (y[4] + e)
"""

@show compiler_state
parse_logical_assignments!(expr, rules, arrays)

## tests for compile_graphppl
expr = bugsmodel"""
    a <- g[2] * 3 + b
    b ~ Normal(g[1], g[2])
"""

parse_logical_assignments!(expr, compiler_state)
parse_stochastic_assignments!(expr, compiler_state)
model = tograph(expr, compiler_state)

# Top level function
compile_graphppl(model_def=expr, data=data)
