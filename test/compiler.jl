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
@run unrollforloops!(expr, compiler_state)
hasforloop(expr, compiler_state)
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

##
data = (x = [8.0, 15.0, 22.0, 29.0, 36.0], xbar = 22, N = 3, T = 2,   
        Y = [151 199; 145 199; 147 214])

expr = bugsmodel"""
    for(i in 1:N) {
        for(j in 1:T) {
            Y[i, j] ~ dnorm(mu[i, j], tau.c)
            mu[i, j] <- alpha[i] + beta[i] * (x[j] - xbar)
        }
        alpha[i] ~ dnorm(alpha.c, alpha.tau)
        beta[i] ~ dnorm(beta.c, beta.tau)
    }
    tau.c ~ dgamma(0.001, 0.001)
    sigma <- 1 / sqrt(tau.c)
    alpha.c ~ dnorm(0.0, 1.0E-6)   
    alpha.tau ~ dgamma(0.001, 0.001)
    beta.c ~ dnorm(0.0, 1.0E-6)
    beta.tau ~ dgamma(0.001, 0.001)
    alpha0 <- alpha.c - xbar * beta.c   
 """
compile_graphppl(model_def=expr, data=data)
##

expr = bugsmodel"""
    a = dmnorm(mu[], T[1:5,1:5])
    b = mean(g[, 5])
"""

dump(expr)
Meta.parse("g[1]")
dump(Meta.parse("h[1, 2:5]"))

Meta.show_sexpr(expr)

compiler_state = CompilerState()

ref_to_symbolic!(Meta.parse("h[1, 2:5]"), compiler_state)
@run ref_to_symbolic!(Meta.parse("h[1, 2:5]"), compiler_state)
compiler_state

##
compiler_state = CompilerState()
ref_to_symbolic!(Meta.parse("h[2, 2:5]"), compiler_state)
##
using PrettyPrinting
pprint(compiler_state.arrays)
@run ref_to_symbolic!(Meta.parse("h[2, 3:6]"), compiler_state)
ref_to_symbolic!(Meta.parse("h[3, 7]"), compiler_state)
ref_to_symbolic!(Meta.parse("h[2, :]"), compiler_state)

##
expr = bugsmodel"""
    if (g) {
        a <- b + c
    }
"""
data = Dict(
    :g => true,
    # :g => false,
    # :g => 1.0,
)
compiler_state = CompilerState()
parsedata!(data, compiler_state)
@show compiler_state;
dump(expr)
Meta.show_sexpr(expr)

@run resolve_if_conditions!(expr, compiler_state)

dump(expr)

##
expr = bugsmodel"""
logit(mu[i]) <- beta0 + beta1 * z1[i] + beta2 * z2[i] + b[i]
"""

lhs_link_function_to_rhs_inverse(expr, nothing)

## 
substitute(a, Dict(a=>b+c, b=>2, c=>3))
compiler_state = CompilerState(
    Dict{Symbol,Array{Num}}(),
    Dict(a=>b+c, b=>2, c=>3),
    Dict{Num,Num}(),
    Dict{Num,Any}(),
)
symbolic_eval(a, compiler_state)