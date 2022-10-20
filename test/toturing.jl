using Random
using SymbolicPPL
using Distributions
using AbstractMCMC
using MCMCChains
using AdvancedMH
using Turing

##
ex = @bugsast begin
    a ~ dnorm(0, 1)
    b ~ dnorm(a, 1)
    c ~ dnorm(b, a^2)
end 

g = compile(ex, (a=1, b=2), :DynamicPPL)
rand(model())

##
ex = @bugsast begin
    a[1] ~ dnorm(0, 1)
    a[2] ~ dnorm(a[1], 1)
    a[3] ~ dnorm(a[2], a[1]^2)
end

g = compile(ex, (a=[1, 2, missing],), :DynamicPPL)
rand(model())
