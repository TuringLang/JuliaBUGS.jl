# For now, naively run the example from README.md

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
