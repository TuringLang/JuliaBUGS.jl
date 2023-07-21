# prepare data
data = JuliaBUGS.BUGSExamples.VOLUME_I[:rats].data
@unpack N, T, x, xbar, Y = data

inits = (alpha = [250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250], beta = [6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6], alpha_c = 150, beta_c = 10, tau_c = 1, alpha_tau = 1, beta_tau = 1)

# prepare models
model_def = @bugsast begin
    for i in 1 : N
        for j in 1 : T
          Y[i, j] ~ dnorm(mu[i, j], tau_c)
          mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(alpha_c, alpha_tau)
        beta[i] ~ dnorm(beta_c, beta_tau)
    end
    tau_c ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau_c)
    alpha_c ~ dnorm(0.0, 1.0E-6)   
    alpha_tau ~ dgamma(0.001, 0.001)
    beta_c ~ dnorm(0.0, 1.0E-6)
    beta_tau ~ dgamma(0.001, 0.001)
    alpha0 = alpha_c - xbar * beta_c
end
bugs_model = compile(model_def, data, inits);
params_vi = JuliaBUGS.get_params_varinfo(bugs_model)

@model function rats(Y, x, xbar, N, T)
    trace = []
    _logp = 0

    tau_c ~ dgamma(0.001, 0.001)
    
    push!(trace, ("tau_c", tau_c, getlogp(__varinfo__)-_logp)); _logp = getlogp(__varinfo__)
    sigma = 1 / sqrt(tau_c)

    alpha_c ~ dnorm(0.0, 1.0E-6)
    push!(trace, ("alpha_c", alpha_c, getlogp(__varinfo__) - _logp)); _logp = getlogp(__varinfo__)
    alpha_tau ~ dgamma(0.001, 0.001)
    push!(trace, ("alpha_tau", alpha_tau, getlogp(__varinfo__) - _logp)); _logp = getlogp(__varinfo__)

    beta_c ~ dnorm(0.0, 1.0E-6)
    push!(trace, ("beta_c", beta_c, getlogp(__varinfo__) - _logp)); _logp = getlogp(__varinfo__)
    beta_tau ~ dgamma(0.001, 0.001)
    push!(trace, ("beta_tau", beta_tau, getlogp(__varinfo__) - _logp)); _logp = getlogp(__varinfo__)

    alpha0 = alpha_c - xbar * beta_c

    alpha = Vector{Real}(undef, N)
    beta = Vector{Real}(undef, N)

    for i in 1:N
        alpha[i] ~ dnorm(alpha_c, alpha_tau)
        push!(trace, ("alpha[$i]", alpha[i], getlogp(__varinfo__) - _logp)); _logp = getlogp(__varinfo__)
        beta[i] ~ dnorm(beta_c, beta_tau)
        push!(trace, ("beta[$i]", beta[i], getlogp(__varinfo__) - _logp)); _logp = getlogp(__varinfo__)

        for j in 1:T
            mu = alpha[i] + beta[i] * (x[j] - xbar)
            Y[i, j] ~ dnorm(mu, tau_c)
            push!(trace, ("Y[$i, $j]", Y[i, j], getlogp(__varinfo__) - _logp)); _logp = getlogp(__varinfo__)
        end
    end

    # return sigma, alpha0
    return trace
end

dppl_model = rats(Y, x, xbar, N, T)
svi = DynamicPPL.evaluate!!(dppl_model, SimpleVarInfo(Dict{VarName, Any}()), DynamicPPL.SamplingContext())[2]
keys(params_vi.values) == keys(svi.values) # test that the parameters match
##
bugs_logp = getlogp(
    evaluate!!(DynamicPPL.settrans!!(bugs_model, false), JuliaBUGS.DefaultContext())
)

@run trace = evaluate!!(DynamicPPL.settrans!!(bugs_model, true), JuliaBUGS.DefaultContext())[2]
trace = [(Symbol(k), v[2], v[1]) for (k, v) in trace]
sort!(trace, by = x -> x[1])
# print `trace` to file
open("/home/sunxd/JuliaBUGS.jl/test/logp_dynamicppl/out1", "w") do io
    for (vn, v, logp) in trace
        println(io, "$vn: $v, $logp")
    end
end

turing_logp = getlogp(
    evaluate!!(dppl_model, settrans!!(params_vi, false), DynamicPPL.DefaultContext())[2]
)

@run trace = evaluate!!(dppl_model, settrans!!(params_vi, true), DynamicPPL.DefaultContext())[1]
sort!(trace, by = x -> x[1])
open("/home/sunxd/JuliaBUGS.jl/test/logp_dynamicppl/out2", "w") do io
    for (vn, v, logp) in trace
        println(io, "$vn: $v, $logp")
    end
end


bugs_logp = getlogp(
    evaluate!!(DynamicPPL.settrans!!(bugs_model, true), JuliaBUGS.DefaultContext())
)

turing_logp = getlogp(
    evaluate!!(dppl_model, settrans!!(params_vi, true), DynamicPPL.DefaultContext())[2]
)


ni = bugs_model.g[@varname(alpha[6])]

@unpack node_type, link_function, node_function, node_args = ni
