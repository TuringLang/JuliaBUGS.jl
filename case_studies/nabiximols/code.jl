using DataFrames
using Plots, StatsPlots
using StatsBase
using JuliaBUGS
using Distributions

using Revise
Revise.includet("juliabugs_code.jl")

##

"""
This dataset contains information from a clinical trial on cannabis dependence treatment. 
It includes 128 participants (id) divided into two treatment groups (group = Placebo or Nabiximols).

Participants underwent a 12-week treatment program with weekly clinical reviews, 
structured counseling, and medication. The Nabiximols group received flexible doses 
up to 32 sprays daily (containing tetrahydrocannabinol and cannabidiol).

The primary outcome measure is the number of cannabis used days (cu) during the 
previous 28 days (set), assessed at weeks 0, 4, 8, and 12 of the trial.
"""

##

id = [1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, 5, 6, 6, 6, 6, 7, 7, 8, 8, 8, 8, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 12, 12, 13, 14, 15, 16, 16, 17, 18, 18, 18, 18, 19, 20, 20, 20, 20, 21, 21, 21, 21, 22, 22, 23, 23, 23, 24, 24, 24, 24, 25, 25, 25, 25, 26, 27, 27, 28, 28, 28, 28, 29, 30, 30, 30, 30, 31, 31, 32, 32, 32, 32, 33, 33, 33, 34, 34, 34, 35, 35, 36, 36, 37, 37, 37, 37, 38, 39, 39, 39, 39, 40, 40, 40, 41, 42, 42, 42, 42, 43, 43, 43, 43, 44, 44, 45, 45, 46, 46, 46, 46, 47, 47, 47, 47, 48, 48, 49, 49, 49, 50, 50, 50, 50, 51, 51, 51, 52, 52, 52, 52, 53, 53, 53, 53, 54, 54, 55, 55, 55, 55, 56, 57, 57, 57, 57, 58, 58, 58, 58, 59, 59, 59, 59, 60, 60, 60, 60, 61, 61, 61, 62, 63, 63, 64, 64, 64, 65, 65, 65, 65, 66, 66, 66, 66, 67, 67, 67, 67, 68, 68, 68, 69, 69, 69, 69, 70, 70, 70, 70, 71, 71, 71, 71, 72, 73, 73, 73, 73, 74, 74, 74, 75, 76, 76, 76, 76, 77, 77, 77, 77, 78, 78, 78, 79, 79, 79, 79, 80, 80, 80, 80, 81, 81, 81, 81, 82, 82, 83, 83, 84, 84, 84, 85, 85, 85, 86, 86, 86, 86, 87, 87, 87, 87, 88, 88, 88, 88, 89, 89, 89, 89, 90, 90, 90, 90, 91, 91, 91, 91, 92, 92, 92, 92, 93, 93, 93, 93, 94, 94, 94, 94, 95, 95, 95, 95, 96, 96, 96, 96, 97, 97, 97, 98, 98, 98, 98, 99, 99, 99, 99, 100, 101, 101, 101, 102, 102, 102, 102, 103, 103, 103, 103, 104, 104, 105, 105, 105, 105, 106, 106, 106, 106, 107, 107, 107, 107, 108, 108, 108, 108, 109, 109, 109, 109, 110, 110, 111, 111, 112, 112, 112, 112, 113, 113, 113, 113, 114, 115, 115, 115, 115, 116, 116, 116, 116, 117, 117, 117, 117, 118, 118, 119, 119, 119, 119, 120, 120, 120, 120, 121, 121, 121, 122, 123, 123, 123, 123, 124, 124, 124, 125, 125, 125, 125, 126, 126, 126, 126, 127, 127, 128]
# 0 for placebo, 1 for nabiximols
group = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0]
week = [0, 4, 8, 12, 0, 4, 8, 0, 4, 8, 0, 4, 8, 12, 0, 4, 0, 4, 8, 12, 0, 4, 0, 4, 8, 12, 0, 4, 8, 0, 4, 8, 12, 0, 4, 8, 0, 4, 0, 0, 0, 0, 4, 0, 0, 4, 8, 12, 0, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0, 4, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 0, 4, 0, 4, 8, 12, 0, 0, 4, 8, 12, 0, 4, 0, 4, 8, 12, 0, 4, 8, 0, 4, 12, 0, 8, 0, 4, 0, 4, 8, 12, 0, 0, 4, 8, 12, 0, 4, 8, 0, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0, 4, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0, 4, 12, 0, 4, 8, 12, 0, 4, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0, 4, 8, 12, 0, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 12, 0, 0, 4, 0, 4, 8, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 0, 4, 8, 12, 0, 4, 8, 0, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0, 4, 0, 4, 8, 0, 4, 8, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 0, 4, 8, 12, 0, 4, 8, 12, 0, 0, 4, 8, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0, 4, 0, 4, 8, 12, 0, 4, 8, 12, 0, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 12, 0, 0, 4, 8, 12, 0, 4, 12, 0, 4, 8, 12, 0, 4, 8, 12, 0, 4, 0]
cu = [13, 12, 12, 12, 28, 0, missing, 16, 9, 2, 28, 28, 28, 28, 28, missing, 28, 28, 17, 28, 28, missing, 16, 0, 0, missing, 28, 28, 28, 28, 17, 0, missing, 28, 27, 28, 28, 26, 24, 28, 28, 28, 25, 28, 26, 28, 18, 16, 28, 28, 7, 0, 2, 28, 2, 4, 1, 28, 28, 16, 28, 28, 24, 26, 15, 28, 25, 17, 1, 8, 28, 24, 27, 28, 28, 28, 28, 28, 27, 28, 28, 28, 28, 20, 28, 28, 28, 28, 12, 28, missing, 17, 15, 14, 28, 0, 28, 28, 28, 0, 0, 0, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 21, 24, 28, 27, 28, 28, 26, missing, 28, missing, 20, 2, 3, 7, 28, 1, 19, 8, 21, 7, 28, 28, 20, 28, 28, 28, 24, 20, 17, 11, 25, 25, 28, 26, 28, 24, 17, 16, 27, 14, 28, 28, 28, 28, 28, 28, 14, 13, 4, 24, 28, 28, 28, 21, 28, 21, 26, 28, 28, 0, 0, 28, 23, 20, 28, 20, 16, 28, 28, 28, 10, 1, 1, 2, 28, 28, 28, 28, 18, 22, 9, 15, 28, 9, 1, 20, 18, 20, 24, 28, 28, 28, 19, 28, 28, 28, 28, 28, 28, 28, 28, 28, 4, 14, 20, 28, 28, 0, 0, 0, 28, 20, 9, 24, 28, 28, 28, 28, 28, 21, 28, 28, 14, 24, 28, 23, 0, 0, 0, 28, missing, 28, missing, 28, 15, missing, 12, 25, missing, 28, 2, 0, 0, 28, 10, 0, 0, 28, 0, 0, 0, 23, 0, 0, 0, 28, 0, 0, 0, 28, 0, 0, 0, 28, 2, 1, 0, 21, 14, 7, 8, 28, 28, 28, 0, 28, 28, 20, 18, 24, 0, 0, 0, 28, 15, missing, 28, 1, 1, 2, 28, 1, 0, 0, 28, 28, 14, 21, 25, 19, 16, 13, 28, 28, 28, 28, 28, 28, 28, 27, 19, 21, 18, 1, 0, 0, 28, 28, 28, 28, 28, 24, 27, 28, 18, 0, 3, 8, 28, 28, 28, 9, 20, 25, 20, 12, 19, 0, 0, 0, 27, 28, 0, 0, 0, 20, 17, 16, 14, 28, 7, 0, 1, 28, 24, 28, 25, 23, 20, 28, 14, 16, 7, 28, 28, 26, 28, 28, 26, 28, 28, 28, 24, 20, 28, 28, 28, 28, 28, 8, 6, 4, 28, 20, 28]
set = fill(28, length(cu))

cu_df = DataFrame(id=id, group=group, week=week, cu=cu)
cu_df_filtered = dropmissing(cu_df, :cu)
df = cu_df_filtered
cu_sd = std(cu_df_filtered.cu)

##

@df cu_df_filtered groupedhist(:cu,
    group=(:group, :week),
    layout=(2, 4),
    bins=-0.5:1:28.5,
    xticks=([0, 10, 20, 28]),
    link=:y,
    ylims=(0, Inf),
    legend=false,
    framestyle=:axes,
    size=(1000, 500)
)

## model 1: normal regression model with varying intercepts for each participant (id)

# brms model  
# brm(formula=cu ~ group * week + (1 | id),
#     data=cu_df,
#     family=gaussian(),
#     prior=c(prior(normal(14, 1.5), class=Intercept),
#         prior(normal(0, 11), class=b),
#         prior(cauchy(1, 2), class=sd)),
#     ...)

model_def = @bugs begin
    # Likelihood: Normal distribution for cannabis use days (cu)
    for i in 1:N
        cu[i] ~ Normal(mu[i], sigma_residual)
        mu[i] = beta[1] + beta[2] * group[i] + beta[3] * week[i] + beta[4] * group[i] * week[i] + alpha[id[i]]
    end

    # Priors

    # Fixed Effects (beta)
    beta[1] ~ Normal(14.0, 1.5)
    for k in 2:4
        beta[k] ~ Normal(0.0, 11.0)
    end

    # Random Effects (alpha) - Varying intercepts for each participant
    for j in 1:N_id
        alpha[j] ~ Normal(0.0, sd_id)
    end

    # Prior for the standard deviation (sd_id) of random intercepts
    # Corresponds to prior(cauchy(1,2), class = sd) in brms.
    sd_id ~ Truncated(Cauchy(1.0, 2.0), 0.0, Inf)

    # Prior for the residual standard deviation (sigma_residual)

    # Option 1: HalfStudentT(3, 0, scale), scaled by data SD
    # sigma_residual ~ truncated(LocationScale(0, cu_sd, TDist(3)), 0.0, Inf)

    # Option 2: Use HalfCauchy or HalfNormal as common weakly informative priors for SD.
    sigma_residual ~ truncated(Cauchy(0, 2.5), 0.0, Inf) # Example: Half-Cauchy with scale 2.5

    # Option 3: Stick with the Gamma-on-precision approach (common in BUGS examples).
    # tau_residual ~ Gamma(0.01, 1.0 / 0.01) # Vague Gamma prior on precision
    # sigma_residual = sqrt(1.0 / tau_residual) # Derive standard deviation
end

# prior predictive checks

prior_check_data = (
    N=length(df.cu),
    N_id=length(unique(df.id)),
    # cu=df.cu, 
    group=df.group,
    week=df.week,
    id=df.id
)

prior_check_model = compile(model_def, prior_check_data)

# samples = sample_from_prior(prior_check_model, 100000);
# mcmcchains = JuliaBUGS.gen_chains(
#     prior_check_model,
#     samples,
#     Symbol[],
#     Vector{Vector{Real}}()
# );

function sample_from_prior(model::JuliaBUGS.BUGSModel, n_samples::Int)
    samples = []
    for i in 1:n_samples
        eval_env, _ = AbstractPPL.evaluate!!(Random.default_rng(), model)
        temp_model = BangBang.setproperty!!(model, :evaluation_env, eval_env)
        params_dict = JuliaBUGS.getparams(temp_model)
        push!(samples, params_dict)
    end
    return samples
end

function sample_from_prior_dict(model::JuliaBUGS.BUGSModel, n_samples::Int)
    samples = Dict{JuliaBUGS.VarName, Any}[]
    for i in 1:n_samples
        eval_env, _ = AbstractPPL.evaluate!!(Random.default_rng(), model)
        temp_model = BangBang.setproperty!!(model, :evaluation_env, eval_env)
        params_dict = JuliaBUGS.getparams(Dict{JuliaBUGS.VarName, Any}, temp_model)
        push!(samples, params_dict)
    end
    return samples
end

samples_dict = sample_from_prior_dict(prior_check_model, 1000);

cu_i_samples = []
for i in 1:length(df.cu)
    vn = JuliaBUGS.VarName{:cu}(JuliaBUGS.IndexLens(i))
    push!(cu_i_samples, [samples_dict[j][vn] for j in 1:length(samples_dict)])
end

# Create a histogram of the prior predictive samples
using Plots

# Plot histograms for a subset of the samples (e.g., first 10 observations)
p = plot(layout=(2, 5), size=(1000, 500), legend=false)
for i in 1:min(10, length(cu_i_samples))
    histogram!(p[i], cu_i_samples[i], title="cu[$i]", 
               xlabel=i > 5 ? "Value" : "", 
               ylabel=i % 5 == 1 ? "Frequency" : "")
end
display(p)

# Plot a combined histogram of all samples
all_samples = vcat(cu_i_samples...)
histogram(all_samples, title="All Prior Predictive Samples", 
          xlabel="Value", ylabel="Frequency", 
          legend=false, alpha=0.7)

data = (
    N=length(df.cu),
    N_id=length(unique(df.id)),
    cu=df.cu,
    group=df.group,
    week=df.week,
    id=df.id
)

normal_model = compile(model_def, data)

using AdvancedHMC, AbstractMCMC
using MCMCChains: MCMCChains
using LogDensityProblems, LogDensityProblemsAD
using ReverseDiff

n_chains = 8
n_samples = 200
n_adapts = 100
ad_normal_model = ADgradient(:ReverseDiff, normal_model; compile=Val(true))
D = LogDensityProblems.dimension(normal_model);
initial_θ = rand(D);

chn = AbstractMCMC.sample(
    ad_normal_model,
    NUTS(0.8),
    AbstractMCMC.MCMCThreads(),
    n_samples,
    n_chains;
    chain_type=MCMCChains.Chains,
    n_adapts=n_adapts,
    init_params=initial_θ,
    discard_initial=n_adapts
)

sub_chn = chn[["beta[1]", "beta[2]", "beta[3]", "beta[4]", "sd_id", "sigma_residual"]]

plot(sub_chn)

MCMCChains.autocorplot(chn)

using ArviZ
using ArviZPythonPlots

data = ArviZ.from_mcmcchains(sub_chn)
data
plot_rank(
    data
)

# posterior predictive checks

# simulation based calibration