using Test

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

test_on(process_variable!, "a.b.c")
test_on(process_variable!, "x ")

test_on(process_expression!, "a.b.c + 1")

test_on(process_assignment!, "x = 1+12")

test_on(process_for!, "for (i in 1:10) { }")

test_on(process_range!, "1:10")

test_on(process_assignment!, "alpha[i] ~ dnorm(alpha.c,alpha.tau)")

test_on(process_indexing!, "[1, 2, 3]");

test_on(process_variable!, "a[1, 2, 3]");

ps = ProcessState("dflat()T(-1000, a[2])")
process_tilde_rhs!(ps)
to_julia_program(ps)

ps = ProcessState("[, 3]")
process_indexing!(ps)
to_julia_program(ps)

function test_process_trivia!()
    # Test 1: Processing whitespace
    ps = ProcessState("   model")
    process_trivia!(ps)
    @test ps.current_index == 2
    @test peek_raw(ps) == "model"

    # Test 2: Processing comments
    ps = ProcessState("# This is a comment\nmodel")
    process_trivia!(ps)
    @test ps.current_index == 3
    @test peek_raw(ps) == "model"

    # Test 3: Not processing newline when skip_newline is false
    ps = ProcessState("\nmodel")
    process_trivia!(ps, false)
    @test ps.current_index == 1
    @test peek_raw(ps) == "\n"

    # Test 4: Processing newline when skip_newline is true
    ps = ProcessState("\nmodel")
    process_trivia!(ps, true)
    @test ps.current_index == 2
    @test peek_raw(ps) == "model"
end


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

parse("""model
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
""")

parse("""
model
   {
      for (i in 1 : K) {
         r0[i] ~ dbin(p0[i], n0[i])
         r1[i] ~ dbin(p1[i], n1[i])
         logit(p0[i]) <- mu[i]
         logit(p1[i]) <- mu[i] + logPsi[i]
         logPsi[i] <- alpha + beta1 * year[i] + beta2 * (year[i] * year[i] - 22) + b[i]
         b[i] ~ dnorm(0, tau)
         mu[i] ~ dnorm(0.0, 1.0E-6)
         cumulative.r0[i] <- cumulative(r0[i], r0[i])
         cumulative.r1[i] <- cumulative(r1[i], r1[i])
      }
      alpha ~ dnorm(0.0, 1.0E-6)
      beta1 ~ dnorm(0.0, 1.0E-6)
      beta2 ~ dnorm(0.0, 1.0E-6)
      tau ~ dgamma(1.0E-3, 1.0E-3)
      sigma <- 1 / sqrt(tau)
   }
""")

parse("""
model
{
#
# Construct individual response data from contingency table
#
   for (i in 1 : Ncum[1, 1]) {
      group[i] <- 1
      for (t in 1 : T) { response[i, t] <- pattern[1, t] }
   }
   for (i in (Ncum[1,1] + 1) : Ncum[1, 2]) {
      group[i] <- 2 for (t in 1 : T) { response[i, t] <- pattern[1, t] }
   }

   for (k in 2 : Npattern) {
      for(i in (Ncum[k - 1, 2] + 1) : Ncum[k, 1]) {
         group[i] <- 1 for (t in 1 : T) { response[i, t] <- pattern[k, t] }
      }
      for(i in (Ncum[k, 1] + 1) : Ncum[k, 2]) {
         group[i] <- 2 for (t in 1 : T) { response[i, t] <- pattern[k, t] }
      }
   }
#
# Model
#
   for (i in 1 : N) {
      for (t in 1 : T) {
         for (j in 1 : Ncut) {
#
# Cumulative probability of worse response than j
#
            logit(Q[i, t, j]) <- -(a[j] + mu[group[i], t] + b[i])
         }
#
# Probability of response = j
#
         p[i, t, 1] <- 1 - Q[i, t, 1]
         for (j in 2 : Ncut) { p[i, t, j] <- Q[i, t, j - 1] - Q[i, t, j] }
         p[i, t, (Ncut+1)] <- Q[i, t, Ncut]

         response[i, t] ~ dcat(p[i, t, ])
         cumulative.response[i, t] <- cumulative(response[i, t], response[i, t])
      }
#
# Subject (random) effects
#
      b[i] ~ dnorm(0.0, tau)
}

#
# Fixed effects
#
   for (g in 1 : G) {
      for(t in 1 : T) {
# logistic mean for group i in period t
         mu[g, t] <- beta * treat[g, t] / 2 + pi * period[g, t] / 2 + kappa * carry[g, t]
      }
   }
   beta ~ dnorm(0, 1.0E-06)
   pi ~ dnorm(0, 1.0E-06)
   kappa ~ dnorm(0, 1.0E-06)

# ordered cut points for underlying continuous latent variable
   a[1] ~ dflat()T(-1000, a[2])
   a[2] ~ dflat()T(a[1], a[3])
   a[3] ~ dflat()T(a[2], 1000)

   tau ~ dgamma(0.001, 0.001)
   sigma <- sqrt(1 / tau)
   log.sigma <- log(sigma)

}
""")
