using TestEnv;
TestEnv.activate();

using JuliaBUGS
using JuliaBUGS: Gibbs, MHFromPrior
using LogDensityProblemsAD, ReverseDiff, Random, AbstractMCMC, AbstractPPL, AdvancedHMC,
      LogDensityProblems, MCMCChains

(; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1.rats
(; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1.pumps
(; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1.dogs

model = compile(model_def, data, inits)
ad_model = ADgradient(:ReverseDiff, model; compile = Val(true))
n_samples, n_adapts = 3000, 1000
initial_θ = rand(LogDensityProblems.dimension(model))
samples_and_stats = AbstractMCMC.sample(
    ad_model,
    NUTS(0.8),
    n_samples;
    chain_type = Chains,
    n_adapts = n_adapts,
    init_params = initial_θ,
    discard_initial = n_adapts
)

# rats: ✓
samples_and_stats[[:alpha0, Symbol("beta.c"), :sigma]]

# pumps: ✓
samples_and_stats

# Dogs
@run AbstractMCMC.step(
    Random.default_rng(),
    AbstractMCMC.LogDensityModel(model),
    Gibbs(model, MHFromPrior())
)

g_spl = Gibbs(model, MHFromPrior())

g_spl.sampler_map

vns = [@varname(alpha)]

@run AbstractPPL.condition(model, vns)

JuliaBUGS.markov_blanket(model.g, vns)
