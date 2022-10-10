using SymbolicPPL
using SymbolicPPL: transform_expr, CompilerState, addlogicalrules!, unroll!, addstochasticrules!, 
ref_to_symbolic!, resolve, ref_to_symbolic, tosymbol, symbolic_eval, scalarize, tograph,
BUGSGraph, tosymbolic, SampleFromPrior
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

@time model = compile(m[:model_def], m[:data], m[:inits][1]);
@run model = compile(m[:model_def], m[:data], m[:inits][1]);
##
expr = transform_expr(m[:model_def]);
compiler_state = CompilerState();
addlogicalrules!(m[:data], compiler_state);

while true
    unroll!(expr, compiler_state) ||
        addlogicalrules!(expr, compiler_state) ||
        break
end
addstochasticrules!(expr, compiler_state);

##
g = tograph(compiler_state);
graph = BUGSGraph(g);

##
sampler = SampleFromPrior()
sample, trace = AbstractMCMC.step(Random.default_rng(), model, sampler);
sample1, trace1 = AbstractMCMC.step(Random.default_rng(), model, sampler, trace);

## run all examples
for m in SymbolicPPL.BUGSExamples.EXAMPLES
    println(m[:name])
    try
        @time model = compile(m[:model_def], m[:data], m[:inits][1]);
    catch e
        println(e)
    end
    try
        sample, trace = AbstractMCMC.step(Random.default_rng(), model, sampler);
    catch e
        println(e)
    end
    println()
end
