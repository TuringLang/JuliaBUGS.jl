using Random
using Distributions
using JuliaBUGS
using JuliaBUGS: @bugs

"""
    synth_hmm_binary(T; pi=[0.5,0.5], trans=[0.8 0.2; 0.2 0.8], mus=[0.0,3.0], sigma=1.0, seed=1)

Generate a length-T binary-state HMM with Normal emissions. Returns `(T=T, y=y)` and truth.
"""
function synth_hmm_binary(T; pi=[0.5,0.5], trans=[0.8 0.2; 0.2 0.8], mus=[0.0,3.0], sigma=1.0, seed=1)
    rng = MersenneTwister(seed)
    S = 2
    y = Vector{Float64}(undef, T)
    z = Vector{Int}(undef, T)
    z[1] = rand(rng, Categorical(pi))
    y[1] = rand(rng, Normal(mus[z[1]], sigma))
    for t in 2:T
        z[t] = rand(rng, Categorical(trans[z[t-1], :]))
        y[t] = rand(rng, Normal(mus[z[t]], sigma))
    end
    truth = (pi=pi, trans=trans, mus=mus, sigma=sigma, z=z)
    return (T=T, y=y), truth
end

"""
    build_hmm2_model()

Return a BUGS model definition for a 2-state HMM with Normal emissions, suitable
for UseAutoMarginalization.
"""
function build_hmm2_model()
    JuliaBUGS.@bugs_primitive Categorical Normal Exponential
    ex = @bugs begin
        mu[1] ~ Normal(0, 5)
        mu[2] ~ Normal(3, 5)
        sigma ~ Exponential(1)

        # Transition matrix via fixed constants (can be learned similarly)
        trans[1, 1] = 0.8
        trans[1, 2] = 0.2
        trans[2, 1] = 0.2
        trans[2, 2] = 0.8
        pi[1] = 0.5
        pi[2] = 0.5

        z[1] ~ Categorical(pi[1:2])
        for t in 2:T
            p[t, 1] = trans[z[t - 1], 1]
            p[t, 2] = trans[z[t - 1], 2]
            z[t] ~ Categorical(p[t, :])
        end
        for t in 1:T
            y[t] ~ Normal(mu[z[t]], sigma)
        end
    end
    return ex
end
