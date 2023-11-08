using JuliaBUGS
using JuliaBUGS: MarkovBlanketBUGSModel, evaluate!!, LogDensityContext
using AbstractMCMC
using AdvancedHMC
using Distributions
using Random
using ReverseDiff
using LogDensityProblems, LogDensityProblemsAD

m = :rats
model_def = JuliaBUGS.BUGSExamples.rats[:model_def]
data = JuliaBUGS.BUGSExamples.rats[:data]
inits = JuliaBUGS.BUGSExamples.rats[:inits][1]
model = compile(model_def, data, inits)

mb_model = MarkovBlanketBUGSModel(model, @varname(var"beta.tau"))
mb_model = MarkovBlanketBUGSModel(model, @varname(alpha[1]))

rng = Random.default_rng()
l = LogDensityProblemsAD.ADgradient(:ReverseDiff, mb_model)
# TODO: this will store TrackedReal into varinfo, do we want this?
t, s = AbstractMCMC.step(
    rng, AbstractMCMC.LogDensityModel(l), HMC(0.1, 10); n_adapts=1, initial_params=[1.0]
)
# this is the same as the step function above
ss = AbstractMCMC.sample(
    AbstractMCMC.LogDensityModel(l),
    HMC(0.1, 10),
    1;
    chain_type=Nothing,
    n_adapts=1,
    initial_params=[1.0],
)

# ! deepcopy varinfo is expensive right now
# logical var values are still evaled, so don't really matter if we keep them consistent all the time - can update the stochastic vars only
# dimension should return the length of the vars under inspection, not the length of all the vars in the Markov blanket
# but we need to keep the value of all the variables in the model
# naturally, because we are saving varinfo anyway, it would be a good storage
# the subtle issue here is the breaking of interface: BUGSModel doesn't use varinfo as state, instead reconstruct it every time given
# the values of the parameters
# but the distinction is blurred

vi, logp = evaluate!!(mb_model, LogDensityContext(), [0.0])
# all values need to be updated, for stochastic variables, the values are not updated, but there distribution is updated, so the score is different

# general "MH-within-Gibbs" sampler
# should store the mapping from a group of variables to the samplers
struct Gibbs <: AbstractSampler
    sampler_map
    # also save the MBs so that we only do it once
end

struct GibbsState
    varinfo # initialize this to be the same as model.varinfo
    # should we store sampler state?
end

ad_backend = :ReverseDiff

# leave HMC integration later: may need to manage `transition` and `state` manually to avoid all the initializations

# initial step
function AbstractMCMC.step(
    rng::Random.AbstractRNG, model::BUGSModel, sampler::Gibbs; kwargs...
)
    state = GibbsState(deepcopy(model.varinfo))

    # The issue here, we want the varinfo to contain the right values:
    # ! LogDensityProblems interface don't allow us to pass "conditioned values"
    # we call HMC and take the updated value and put it into varinfo to maintain consistancy 
    # do a loop through all the variable partitions
    for (var_group, sampler) in sampler.sampler_map
        p = LogDensityProblemsAD.ADgradient(
            ad_backend, MarkovBlanketBUGSModel(model, var_group)
        )
        state = last(AbstractMCMC.step(rng, model_local, sampler_local; kwargs...))
        # TODO: we can assume AHMC here, do need to work on other integration

    end
end

# the parents and coparents' logp don't change
# question is: when does it matter? We are using the values, 

function AbstractMCMC.step(
    rng::Random.AbstractRNG, model::BUGSModel, sampler::Gibbs, state; kwargs...
)
end

# TODO: another way to do this is to keep all the vales, and the LogDensityProblems takes all the : the LDP dimension still mismatch
# I don't want to "first set and then compute": defeats the purpose because it touch things twice 
# workaround: use model to pass in value?

# TODO this week
# benchmark and do some maintenance
# think about the arrays -- worse case, we want to store things sequentially, 
# also better to have a way to tell which vars are data