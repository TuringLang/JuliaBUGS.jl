using JuliaBUGS

(; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats
model = compile(model_def, data, inits)

@doc Tapir.TestUtils.test_rule

using Random
Tapir.TestUtils.test_rule(
    Random.default_rng(),
    LogDensityProblems.logdensity,
    model,
    rand(65);
    perf_flag=:none,
    is_primitive=false,
    interp=Tapir.TapirInterpreter(),
)

ad_model = ADgradient(AutoTapir(), model)
LogDensityProblems.logdensity_and_gradient(
    ad_model, rand(LogDensityProblems.dimension(model))
)

# Attempts at creating a MWE for the JuliaBUGS-Tapir error
using ADTypes, Tapir, LogDensityProblems, LogDensityProblemsAD

# an error in the stack trace is point to `getindex` in `MetaGraphsNext`, so creating MWE around it
using Graphs, MetaGraphsNext

struct GraphWrapper
    g::MetaGraph
end

struct NodeType{F}
    f::F
    val::Float64
end

g = MetaGraph(DiGraph(); label_type=Symbol, vertex_data_type=NodeType)
add_vertex!(g, :a, NodeType(x -> x * 2, 1.0))
add_vertex!(g, :b, NodeType(x -> x * 3, 2.0))

function LogDensityProblems.logdensity(gw::GraphWrapper, x)
    return only(x) * gw.g[:a].f(gw.g[:a].val) * gw.g[:b].f(gw.g[:b].val)
end

ad_f = ADgradient(AutoTapir(), GraphWrapper(g))
LogDensityProblems.logdensity_and_gradient(ad_f, [2.0])
