function test_on(f, str)
    ps = ProcessState(str)
    f(ps)
    if ps.current_index > length(ps.token_vec)
        println("finished")
    else
        println("next token: $(untokenize(ps.token_vec[ps.current_index], ps.text))", )
    end
    # @show ps.julia_token_vec
    println(to_julia_program(ps.julia_token_vec, ps.text))
    io = IOBuffer()
    JuliaSyntax.show_diagnostics(io, ps.diagnostics, ps.text)
    println(String(take!(io)))
    return ps
end

test_on(process_toplevel!, "model { } ")

test_on(process_trivia!, "  \n  a")

test_on(process_variable!, "a.b.c")
test_on(process_variable!, "x ")

test_on(process_expression!, "a.b.c + 1")

test_on(process_assignment!, "x = 1+12")

test_on(process_for!, "for (i in 1:10) { }")

test_on(process_range!, "1:10")

ps = test_on(process_assignment!, """
    alpha[i] ~ dnorm(alpha.c,alpha.tau)
""");

test_on(process_toplevel!, """model
{
   for( i in 1 : N ) {
      for( j in 1 : T ) {
         Y[i , j] ~ dnorm(mu[i , j],tau.c)
      }
      alpha[i] ~ dnorm(alpha.c,alpha.tau)
   }
}
""")

test_on(process_toplevel!, """model
{
    for( i in 1 : N ) {
        for( j in 1 : T ) {
           Y[i , j] ~ dnorm(mu[i , j],tau.c)
           mu[i , j] <- alpha[i] + beta[i] * (x[j] - xbar)
        }
        alpha[i] ~ dnorm(alpha.c,alpha.tau)
        beta[i] ~ dnorm(beta.c,beta.tau)
     }
     tau.c ~ dgamma(0.001,0.001)
     sigma <- 1 / sqrt(tau.c)
     alpha.c ~ dnorm(0.0,1.0E-6)   
     alpha.tau ~ dgamma(0.001,0.001)
     beta.c ~ dnorm(0.0,1.0E-6)
     beta.tau ~ dgamma(0.001,0.001)
     alpha0 <- alpha.c - xbar * beta.c   
}
"""
);

test_on(process_indexing!, "[1, 2, 3]");
test_on(process_variable!, "a[1, 2, 3]");

parse("""model
{
    for i in 1 : N ) {
        for( j in 1 : T ) {
           Y[i , j] ~ dnorm(mu[i , j],tau.c)
           mu[i , j] <- alpha[i] + beta[i] * (x[j] - xbar)
        }
        alpha[i] ~ dnorm(alpha.c,alpha.tau)
        beta[i] ~ dnorm(beta.c,beta.tau)
     }
     tau.c ~ dgamma(0.001,0.001)
     sigma <- 1 / sqrt(tau.c)
     alpha.c ~ dnorm(0.0,1.0E-6)   
     alpha.tau ~ dgamma(0.001,0.001)
     beta.c ~ dnorm(0.0,1.0E-6)
     beta.tau ~ dgamma(0.001,0.001)
     alpha0 <- alpha.c - xbar * beta.c   
}
""")