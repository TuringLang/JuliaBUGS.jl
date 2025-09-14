#!/usr/bin/env julia
using AutoMarginalizationExperiments
using JuliaBUGS
using ADTypes
using Distributions
using ForwardDiff
using LogExpFunctions
using LogDensityProblems
using LogDensityProblemsAD
using Printf

function main(; N=12, K=2, seed=1)
    data, truth = AutoMarginalizationExperiments.synth_gmm(N; seed=seed, weights=fill(1/K,K), mus=collect(range(-1.0,1.0; length=K)), sigmas=fill(0.8, K))
    dataK = (data..., K=K)
    model_def = AutoMarginalizationExperiments.build_gmm_model(K)
    model, θ = AutoMarginalizationExperiments.compile_autmarg(model_def, dataK)
    ad_model = ADgradient(AutoForwardDiff(), model)

    # Build mapping from θ to variable values
    gd = model.graph_evaluation_data
    # Continuous parameters only
    cont_vars = JuliaBUGS.Model.VarName[]
    for vn in gd.sorted_parameters
        idx = findfirst(==(vn), gd.sorted_nodes)
        if idx !== nothing && gd.node_types[idx] == :continuous
            push!(cont_vars, vn)
        end
    end
    var_lengths = Dict{JuliaBUGS.Model.VarName,Int}()
    for vn in cont_vars
        var_lengths[vn] = model.transformed_var_lengths[vn]
    end
    offsets = Dict{JuliaBUGS.Model.VarName,Int}()
    start = 1
    for vn in cont_vars
        offsets[vn] = start
        start += var_lengths[vn]
    end

    function unpack(θvec)
        T = eltype(θvec)
        mus = fill(zero(T), K)
        sigmas = fill(zero(T), K)
        for vn in cont_vars
            name = string(vn)
            s = offsets[vn]
            # parse index inside brackets
            idx = try parse(Int, name[findfirst('[', name)+1:findfirst(']', name)-1]) catch; 0 end
            if startswith(name, "mu[") && idx ≥ 1 && idx ≤ K
                mus[idx] = θvec[s]
            elseif startswith(name, "sigma[") && idx ≥ 1 && idx ≤ K
                sigmas[idx] = exp(θvec[s])
            end
        end
        return mus, sigmas
    end

    function logjoint_closed(θvec)
        mus, sigmas = unpack(θvec)
        @assert length(mus) == K && length(sigmas) == K
        # Priors: mu ~ Normal(0,5), sigma ~ Exponential(1) with log-Jacobian from exp transform
        lp = 0.0
        for k in 1:K
            lp += logpdf(Distributions.Normal(0,5), mus[k])
            lp += logpdf(Distributions.Exponential(1.0), sigmas[k]) + log(sigmas[k]) # jacobian of exp
        end
        # Likelihood: product over i of sum_k w_k N(y_i | mu_k, sigma_k)
        w = 1.0 / K
        for yi in data.y
            terms = similar(mus)
            @inbounds for k in 1:K
                terms[k] = log(w) + logpdf(Distributions.Normal(mus[k], sigmas[k]), yi)
            end
            lp += LogExpFunctions.logsumexp(terms)
        end
        return lp
    end

    val_ad, grad_ad = LogDensityProblems.logdensity_and_gradient(ad_model, θ)
    val_cf = logjoint_closed(θ)
    grad_cf = ForwardDiff.gradient(logjoint_closed, θ)

    @printf "N=%d, K=%d\n" N K
    @printf "value: engine=%.8f, closed=%.8f, absdiff=%.3e\n" val_ad val_cf abs(val_ad - val_cf)
    @printf "grad max-abs-diff: %.3e\n" maximum(abs.(grad_ad .- grad_cf))
end

main()
