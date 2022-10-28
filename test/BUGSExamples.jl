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

sampler = ProposeFromPrior()
s, state = AbstractMCMC.step(Random.default_rng(), model, sampler);
s, state = AbstractMCMC.step(Random.default_rng(), model, sampler, state);

g = compile(m[:model_def], m[:data], :DynamicPPL);
using Turing; chn = sample(g(), HMC(0.1, 5), 12000, discard_initial = 1000)
chn[[:d, Symbol("delta.new"), :tau]] # blockers