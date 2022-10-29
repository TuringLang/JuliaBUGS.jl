using SymbolicPPL
using SymbolicPPL: ProposeFromPrior
using Random
using AbstractMCMC
##

m = SymbolicPPL.BUGSExamples.EXAMPLES[:blockers];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:bones];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:dogs];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:dyes];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:epil];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:equiv];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:inhalers];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:kidney];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:leuk];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:leukfr];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:lsat];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:magnesium];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:mice];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:oxford];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:pumps];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:rats];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:salm];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:seeds];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:stacks];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:surgical_simple];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:surgical_realistic];

@time g = compile(m[:model_def], m[:data], :Graph);
@run g = compile(m[:model_def], m[:data], :Graph);

model = SymbolicPPL.GraphModel(g);
sampler = ProposeFromPrior()
s, state = AbstractMCMC.step(Random.default_rng(), model, sampler);
s, state = AbstractMCMC.step(Random.default_rng(), model, sampler, state);

model = SymbolicPPL.todppl(g)
using Turing; chn = sample(model(), NUTS(), 12000, discard_initial = 1000)

# blockers
chn[[:d, Symbol("delta.new"), :tau]] # blockers
using MCMCChains; Chains(map(x->1/sqrt(x), chn[[:tau]].value)) # sigma