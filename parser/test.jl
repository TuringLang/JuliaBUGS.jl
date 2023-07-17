using Test

prog = """model
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

tv = tokenize(prog)

jp = ""
for t in tv
    jp = jp * untokenize(t, prog)
end
println(jp)

JuliaSyntax.Token(JuliaSyntax.SyntaxHead(K"EndMarker", JuliaSyntax.EMPTY_FLAGS), 0:0)
Token(SyntaxHead(K"EndMarker", EMPTY_FLAGS), 0:0)

@testset "skip_trivia!" begin
    text = "  \n a"
    tv = tokenize(text)
    diagnostics = []
    jp = []
    loc = skip_trivia!(tv1, 1, text, jp, diagnostics)
    @show loc
    @show jp
end

@testset "expect!" begin
    text = "{}"
    tv = tokenize(text)
    diagnostics = []
    jp = []
    loc = expect!(tv, 1, text, jp, diagnostics, K"{", false)
    @show loc
    @show jp
    loc = expect!(tv, loc, text, jp, diagnostics, K"}", true, "end")
    @show loc
    @show jp
end

"""
model {
    a ~ b
    c <- d
}
"""

# missing {
"""
model 
    a ~ b
    c <- d
}
"""

"""
model {
    a ~ b
    c <- d
"""

# got something outside
"""
model {
    a ~ b
    c <- d
}
a ~ b
"""

Meta.parse("  ")

text = "model a "
tv = tokenize(text)
diagnostics = Diagnostic[]
jp = []
loc = process_toplevel!(tv, 1, text, jp, diagnostics)
diagnostics
JuliaSyntax.show_diagnostics(io, diagnostics, text)
io = IOBuffer()
take!(io) |> String

text = "a.b.c + b\n"
tv = tokenize(text)
diagnostics = []
jp = []
loc = process_expressions!(tv, 1, text, jp, diagnostics)
jp

function f(a)
    a[] = a[] + 1
end

a = Ref(0)
f(a)
a

using JuliaSyntax
using JuliaSyntax: parse!, ParseStream

ps = ParseStream("""
    function f(x)
        y = x .+ 1
        return y
    end
""")

parse!(ps)

dump(ps)

# 
function f(x)
    @label global_return
    g(x)
    print("finish")
end

function g(x)
    while true
        x = x + 1
        if x > 10
            @goto global_return
        end
    end
end