using SymbolicPPL
using SymbolicPPL:
    CompilerState,
    resolveif!,
    inverselinkfunction,
    unrollforloops!,
    tosymbolic,
    resolve,
    symbolic_eval,
    ref_to_symbolic!,
    addlogicalrules!,
    addstochasticrules!,
    tograph,
    compile_graphppl
using Test
using Symbolics

##

# tests for `addlogicalrules` for data
data = Dict(:N => 2, :g => [1, 2, 3])

compiler_state = CompilerState()
addlogicalrules!(data, compiler_state)
@test compiler_state.logicalrules[tosymbolic(:N)] == Num(2)
@test compiler_state.logicalrules[ref_to_symbolic!("g[3]")] == Num(3)
@test resolve(:N, compiler_state) == 2
@test resolve(ref_to_symbolic!("g[2]"), compiler_state) == 2

# tests for unrolling facilities
expr = bugsmodel"""      
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

intended_result = bugsmodel"""
    variable.0 <- 1
    array.variable.0[1] <- 1
    array.variable.1[1] <- 1 + 1
    array.variable.2[1, 1, 1] <- 2
    array.variable.2[1, 2, 1] <- 2
    array.variable.2[1, 2, 2] <- 2
    array.variable.0[2] <- 1
    array.variable.1[2] <- 2 + 1
    array.variable.2[2, 1, 1] <- 2
    array.variable.2[2, 2, 1] <- 2
    array.variable.2[2, 2, 2] <- 2
    array.variable.0[3] <- 1
    array.variable.1[3] <- 3 + 1
    array.variable.2[3, 1, 1] <- 2
    array.variable.2[3, 2, 1] <- 2
    array.variable.2[3, 2, 2] <- 2
    array.variable.3[1] <- 1
    array.variable.3[2] <- 2
    array.variable.4[1] <- 1
    array.variable.4[2] <- 2
    variable.1 <- 1
"""
@test expr == intended_result

# tests for unrolling: corner case where need variable defined in outer loop to unroll inner loop
# rely on `N` was defined to be 2 from previous tests 
expr = bugsmodel"""      
    for (i in 1:N) {
        n[i] = i
        for(j in 1:n[i]) {
            m[i, j] = i + j
        }
    }     
"""
unrollforloops!(expr, compiler_state)
addlogicalrules!(expr, compiler_state)
unrollforloops!(expr, compiler_state)

intended_result = bugsmodel"""
    n[1] = 1
    m[1, 1] = 1 + 1
    n[2] = 2
    m[2, 1] = 2 + 1
    m[2, 2] = 2 + 2
"""

@test expr == intended_result

# tests for `ref_to_symbolic!`
# case 1: g[1] already exists
@test Symbolics.isequal(
    ref_to_symbolic!(Meta.parse("g[1]"), compiler_state),
    tosymbolic(Meta.parse("g[1]")),
)
# case 2: g[4] doesn't exist, so expand compiler_state.arrays
@test Symbolics.isequal(
    ref_to_symbolic!(Meta.parse("g[4]"), compiler_state),
    tosymbolic(Meta.parse("g[4]")),
)
@test Symbolics.isequal(compiler_state.arrays[:g][4], tosymbolic(Meta.parse("g[4]")))
# case 3: array h doesn't exist, create one
@test :h ∉ keys(compiler_state.arrays)
ref_to_symbolic!(Meta.parse("h[2]"), compiler_state)
@test Symbolics.isequal(compiler_state.arrays[:h][2], tosymbolic(Meta.parse("h[2]")))
# case 4: slicing 
s = ref_to_symbolic!(Meta.parse("s[2, 3:6]"), compiler_state)
@test size(s) == (4,)
s = ref_to_symbolic!(Meta.parse("s[2, :]"), compiler_state)
@test size(s) == (6,)
s = ref_to_symbolic!(Meta.parse("s[2:3, :]"), compiler_state)
@test size(s) == (2, 6)
s = ref_to_symbolic!(Meta.parse("s[N-1, :]"), compiler_state)
@test size(s) == (6, )

# tests for parse_logical_assignments!
expr = bugsmodel"""
    v[2] <- h[3] + (g[2] * d) * c
    w[6] <- f[2] / (y[4] + e)
"""

addlogicalrules!(expr, compiler_state)
@variables c d
intended_equation = tosymbolic(Meta.parse("h[3]")) + c * d * tosymbolic(Meta.parse("g[2]"))
@test Symbolics.isequal(
    compiler_state.logicalrules[tosymbolic(Meta.parse("v[2]"))],
    intended_equation,
)

# tests for `if`
# note: `if` implemented simply test if the condition evals to true, and then decides to add the exprs in or leave out 
expr = bugsmodel"""
    if (condt) {
        exprt <- 0
    }
    if (condf) {
        exprf <- 0
    }
"""
data = Dict(:condt => true, :condf => false)
compiler_state = CompilerState()
addlogicalrules!(data, compiler_state)
resolveif!(expr, compiler_state)
intended_expr = bugsmodel"""
    exprt <- 0
"""
@test expr == intended_expr

# test for link function handling
expr = bugsmodel"""
    logit(lhs) <- rhs
    cloglog(lhs) <- rhs
    log(lhs) <- rhs
    probit(lhs) <- rhs
"""

intended_expr = bugsmodel"""
    lhs <- logistic(rhs)
    lhs <- cexpexp(rhs)
    lhs <- exp(rhs)
    lhs <- phi(rhs)
"""
@test inverselinkfunction(expr) == intended_expr

# test for symbolic_eval
@variables a b c
compiler_state = CompilerState(
    Dict{Symbol,Array{Num}}(),
    Dict(a => b + c, b => 2, c => 3),
    Dict{Num,Num}(),
    Dict{Num,Any}(),
)
@test symbolic_eval(a, compiler_state) == 5

# test for the top function
# example taken from https://chjackson.github.io/openbugsdoc/Examples/Rats.html (data simplified)
data = (
    x = [8.0, 15.0, 22.0, 29.0, 36.0],
    xbar = 22,
    N = 3,
    T = 2,
    Y = [151 199; 145 199; 147 214],
)

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

model = compile_graphppl(model_def = expr, data = data, initials=NamedTuple())

## 
using SymbolicPPL
m = SymbolicPPL.BUGSExamples.EXAMPLES[:pumps];
model = compile_graphppl(model_def = m[:model_def], data = m[:data], initials = m[:inits][1]);
@run model = compile_graphppl(model_def = m[:model_def], data = m[:data], initials = m[:inits][1]);
print(collect(keys(model)))
