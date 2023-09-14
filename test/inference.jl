# ReverseDiff

# tape compilation for trans-dim bijectors
# `birats` contains Dirichlet distribution 

model_def = JuliaBUGS.BUGSExamples.birats.model_def;
data = JuliaBUGS.BUGSExamples.birats.data;
inits = JuliaBUGS.BUGSExamples.birats.inits[1];
model = compile(model_def, data, inits);
ad_model = ADgradient(:ReverseDiff, model; compile=Val(false));
D = LogDensityProblems.dimension(model); initial_θ = rand(D)
LogDensityProblems.logdensity_and_gradient(ad_model, initial_θ)
# if no error is thrown, then the test passes

# AdvancedHMC

# test generation of parameter names
model = compile(
    (@bugs begin
        x[1:2] ~ dmnorm(mu[:], sigma[:, :])
        x[3] ~ dnorm(0, 1)
        y = x[1] + x[3]
    end), (mu=[0, 0], sigma=[1 0; 0 1]), NamedTuple()
)

ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))
n_samples, n_adapts = 10, 0
D = LogDensityProblems.dimension(model);
initial_θ = rand(D);
samples_and_stats = AbstractMCMC.sample(
    ad_model,
    NUTS(0.8),
    n_samples;
    chain_type=Chains,
    n_adapts=n_adapts,
    init_params=initial_θ,
    discard_initial=n_adapts,
)

@test samples_and_stats.name_map.parameters ==
    [Symbol("x[3]"), Symbol("x[1:2][1]"), Symbol("x[1:2][2]"), :y]

# test inference result with Seeds 
data = JuliaBUGS.BUGSExamples.VOLUME_I[:seeds].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:seeds].inits[1]
model = JuliaBUGS.compile(JuliaBUGS.BUGSExamples.VOLUME_I[:seeds].model_def, data, inits)

ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

n_samples, n_adapts = 2000, 1000

D = LogDensityProblems.dimension(model);
initial_θ = rand(D);

samples_and_stats = AbstractMCMC.sample(
    ad_model,
    NUTS(0.8),
    n_samples;
    chain_type=Chains,
    n_adapts=n_adapts,
    init_params=initial_θ,
    discard_initial=n_adapts,
)

@test summarize(samples_and_stats)[:alpha0].nt.mean[1] ≈ -0.5499 rtol = 0.1
@test summarize(samples_and_stats)[:alpha0].nt.std[1] ≈ 0.1965 rtol = 0.1

@test summarize(samples_and_stats)[:alpha1].nt.mean[1] ≈ 0.08902 rtol = 0.1
@test summarize(samples_and_stats)[:alpha1].nt.std[1] ≈ 0.3124 rtol = 0.1

@test summarize(samples_and_stats)[:alpha12].nt.mean[1] ≈ -0.841 rtol = 0.1
@test summarize(samples_and_stats)[:alpha12].nt.std[1] ≈ 0.4372 rtol = 0.1

@test summarize(samples_and_stats)[:alpha2].nt.mean[1] ≈ 1.356 rtol = 0.1
@test summarize(samples_and_stats)[:alpha2].nt.std[1] ≈ 0.2772 rtol = 0.1

@test summarize(samples_and_stats)[:sigma].nt.mean[1] ≈ 0.2922 rtol = 0.1
@test summarize(samples_and_stats)[:sigma].nt.std[1] ≈ 0.1467 rtol = 0.1
