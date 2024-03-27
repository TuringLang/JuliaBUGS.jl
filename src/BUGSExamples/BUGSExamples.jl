module BUGSExamples

using JuliaBUGS: @bugs

struct Example
    name::String
    model_def::Expr
    data::NamedTuple
    inits::NamedTuple
    inits_alternative::NamedTuple
    reference_results::Union{NamedTuple, Nothing}
end

function load_examples(volume_num::Int)
    example_set = NamedTuple()
    if volume_num == 1 || volume_num == 0
        include("Volume_1/Blocker.jl")
        include("Volume_1/Bones.jl")
        include("Volume_1/Dogs.jl")
        include("Volume_1/Dyes.jl")
        include("Volume_1/Epil.jl")
        include("Volume_1/Equiv.jl")
        include("Volume_1/Inhalers.jl")
        include("Volume_1/Kidney.jl")
        include("Volume_1/Leuk.jl")
        include("Volume_1/LeukFr.jl")
        include("Volume_1/LSAT.jl")
        include("Volume_1/Magnesium.jl")
        include("Volume_1/Mice.jl")
        include("Volume_1/Oxford.jl")
        include("Volume_1/Pumps.jl")
        include("Volume_1/Rats.jl")
        include("Volume_1/Salm.jl")
        include("Volume_1/Seeds.jl")
        include("Volume_1/Stacks.jl")
        include("Volume_1/Surgical.jl")
        example_set = merge(example_set,
            (
                blockers = blockers,
                bones = bones,
                dogs = dogs,
                dyes = dyes,
                epil = epil,
                equiv = equiv,
                # inhalers=inhalers, # use Chain graph, not supported
                kidney = kidney,
                leuk = leuk,
                leukfr = leukfr,
                lsat = lsat,
                magnesium = magnesium,
                mice = mice,
                oxford = oxford,
                pumps = pumps,
                rats = rats,
                salm = salm,
                seeds = seeds,
                stacks = stacks,
                surgical_simple = surgical_simple,
                surgical_realistic = surgical_realistic
            ))
    end

    if volume_num == 2 || volume_num == 0
        include("Volume_2/BiRats.jl")
        include("Volume_2/Eyes.jl")
        example_set = merge(example_set, (
            birats = birats,
            eyes = eyes
        ))
    end

    return example_set
end

const VOLUME_1 = load_examples(1)
const VOLUME_2 = load_examples(2)

end

println(JuliaBUGS.to_julia_program( """
# Set up data
for(i in 1 : N) {
    for(j in 1 : T) {
        # risk set = 1 if obs.t >= t
        Y[i, j] <- step(obs.t[i] - t[j] + eps)
        
        # counting process jump = 1 if obs.t in [ t[j], t[j+1] )
        # i.e. if t[j] <= obs.t < t[j+1]
        dN[i, j] <- Y[i, j ] * step(t[j+1] - obs.t[i] - eps) * fail[i]
    }
}

# Model
for(j in 1 : T) {
    for(i in 1 : N) {
        dN[i, j] ~ dpois(Idt[i, j])
        Idt[i, j] <- Y[i, j] * exp(beta * Z[i]+b[pair[i]]) * dL0[j]
    }
    dL0[j] ~ dgamma(mu[j], c)
    mu[j] <- dL0.star[j] * c # prior mean hazard
    
    # Survivor function = exp(-Integral{l0(u)du})^exp(beta * z)
    S.treat[j] <- pow(exp(-sum(dL0[1 : j])), exp(beta * -0.5))
    S.placebo[j] <- pow(exp(-sum(dL0[1 : j])), exp(beta * 0.5))   
}
for(k in 1 : Npairs) {
    b[k] ~ dnorm(0.0, tau);
}
tau ~ dgamma(0.001, 0.001)
sigma <- sqrt(1 / tau)
c <- 0.001 
r <- 0.1
for (j in 1 : T) {
    dL0.star[j] <- r * (t[j+1]-t[j])
}
beta ~ dnorm(0.0,0.000001)
""", false, true))