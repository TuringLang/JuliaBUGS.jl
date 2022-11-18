using SymbolicPPL
using AbstractMCMC
using MCMCChains
using Random
using Turing
##

# Volume 1
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

# Volume 2
m = SymbolicPPL.BUGSExamples.EXAMPLES[:eyes];
m = SymbolicPPL.BUGSExamples.EXAMPLES[:birats];

g, inits = compile(m[:model_def], m[:data], :Graph);
model = SymbolicPPL.todppl(g);
d, c = SymbolicPPL.gen_variation_partition(g);

chn = sample(
    model(),
    Gibbs(MH(d...), HMC(0.05, 3, c...)),
    10000;
    # discard_initial = 1000
)

e = @bugsast begin
    a ~ dnorm(0, 1)
    b ~ dnorm(a, 1)
    c ~ dnorm(b, a)
    b = 1
end

g, _ = compile(e, NamedTuple(), :Graph)

TikzGraphs.plot(g)