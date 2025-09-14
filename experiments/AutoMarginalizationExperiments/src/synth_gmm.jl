using Random
using Distributions
using JuliaBUGS
using JuliaBUGS: @bugs, compile, settrans

"""
    synth_gmm(N; weights=[0.3,0.7], mus=[-2.0, 2.0], sigmas=[1.0, 1.0], seed=1)

Generate synthetic data for a univariate K-component GMM.
Returns `(N=N, y=y)` and ground truth NamedTuple.
"""
function synth_gmm(N; weights=[0.3,0.7], mus=[-2.0, 2.0], sigmas=[1.0, 1.0], seed=1)
    rng = MersenneTwister(seed)
    K = length(weights)
    y = Vector{Float64}(undef, N)
    cdist = Categorical(weights)
    for i in 1:N
        k = rand(rng, cdist)
        y[i] = rand(rng, Normal(mus[k], sigmas[k]))
    end
    truth = (weights=weights, mus=mus, sigmas=sigmas)
    return (N=N, y=y), truth
end

"""
    build_gmm_model(K)

Return a BUGS model definition for a K-component univariate GMM with discrete
assignments z[i]. Suitable for UseAutoMarginalization.
"""
function build_gmm_model(K::Integer)
    # Ensure primitives are registered for this module
    JuliaBUGS.@bugs_primitive Categorical Normal Exponential
    ex = @bugs begin
        # Equal weights by default; can be learned if needed via Dirichlet
        for k in 1:K
            w[k] = 1.0 / K
        end
        for k in 1:K
            mu[k] ~ Normal(0, 5)
            sigma[k] ~ Exponential(1)
        end
        for i in 1:N
            z[i] ~ Categorical(w[1:K])
            y[i] ~ Normal(mu[z[i]], sigma[z[i]])
        end
    end
    return ex
end
