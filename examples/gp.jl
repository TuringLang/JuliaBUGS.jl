using JuliaBUGS
using JuliaBUGS: @model
using AbstractGPs, Distributions, LogExpFunctions

golf_data = (
    distance=[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
    n=[
        1443,
        694,
        455,
        353,
        272,
        256,
        240,
        217,
        200,
        237,
        202,
        192,
        174,
        167,
        201,
        195,
        191,
        147,
        152,
    ],
    y=[1346, 577, 337, 208, 149, 136, 111, 69, 67, 75, 52, 46, 54, 28, 27, 31, 33, 20, 24],
)

data = (
    d=golf_data.distance,
    n=golf_data.n,
    y=golf_data.y,
    jitter=1e-6,
    N=length(golf_data.distance),
)

@model function gp_golf_putting((; v, l, f_latent, y), N, n, d, jitter)
    v ~ Distributions.Gamma(2, 1)
    l ~ Distributions.Gamma(4, 1)
    f_latent[1:N] ~ gp_predict(v, l, d[1:N], jitter)
    y[1:N] ~ y_distribution(n[1:N], f_latent[1:N])
end

JuliaBUGS.@register_primitive GP with_lengthscale SEKernel

# all variables have numerical types in BUGS, so we write a function that returns the GP predictions
JuliaBUGS.@register_primitive function gp_predict(v, l, d, jitter)
    return GP(v * with_lengthscale(SEKernel(), l))(d, jitter)
end

JuliaBUGS.@register_primitive function y_distribution(n, f_latent)
    return product_distribution(Binomial.(n, logistic.(f_latent)))
end

model = gp_golf_putting(
    (; v=missing, l=missing, f_latent=fill(missing, data.N), y=data.y),
    data.N,      # number of observations
    data.n,       # Observed attempts
    data.d,      # Observed distances
    data.jitter, # Numerical stability term
)
model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())

using LogDensityProblems, LogDensityProblemsAD
using AbstractMCMC, AdvancedHMC
using MCMCChains

using DifferentiationInterface
using Mooncake: Mooncake

struct BUGSMooncakeModel{T,P}
    model::T
    prep::P
end

f(x) = model.log_density_computation_function(model.evaluation_env, x)
backend = AutoMooncake(; config=nothing)
x = rand(LogDensityProblems.dimension(model))
prep = prepare_gradient(f, backend, x)
gradient(f, prep, backend, x)

bugsmooncake = BUGSMooncakeModel(model, prep)

function LogDensityProblems.logdensity(model::BUGSMooncakeModel, x::AbstractVector)
    return f(x)
end
function LogDensityProblems.logdensity_and_gradient(
    model::BUGSMooncakeModel, x::AbstractVector
)
    return DifferentiationInterface.value_and_gradient(
        f, model.prep, AutoMooncake(; config=nothing), x
    )
end
function LogDensityProblems.dimension(model::BUGSMooncakeModel)
    return LogDensityProblems.dimension(model.model)
end
function LogDensityProblems.capabilities(::BUGSMooncakeModel)
    return LogDensityProblems.LogDensityOrder{2}()
end

@benchmark LogDensityProblems.logdensity_and_gradient($bugsmooncake, $x)

using ReverseDiff

ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

samples_and_stats = AbstractMCMC.sample(
    # ad_model,
    AbstractMCMC.LogDensityModel(bugsmooncake),
    AdvancedHMC.NUTS(0.65),
    1500;
    chain_type=Chains,
    n_adapts=500,
    discard_initial=500,
)
