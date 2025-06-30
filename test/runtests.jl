using Test

using ADTypes
using AbstractPPL
using Bijectors
using ChainRules # needed for `Bijectors.cholesky_lower`
using Distributions
using Documenter
using Graphs
using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BUGSPrimitives: mean
using LinearAlgebra
using LogDensityProblems
using LogDensityProblemsAD
using MacroTools
using MetaGraphsNext
using OrderedCollections
using Random
using Serialization
using StableRNGs

using AbstractMCMC
using AdvancedHMC
using AdvancedMH
using MCMCChains
using ReverseDiff

const TEST_GROUPS = OrderedDict{String,Function}(
    "elementary" => () -> begin
        Documenter.doctest(JuliaBUGS; manual=false)
        include("BUGSPrimitives/distributions.jl")
        include("BUGSPrimitives/functions.jl")
    end,
    "frontend" => () -> begin
        include("parser/bugs_macro.jl")
        include("parser/bugs_parser.jl")
        include("compiler_pass.jl")
        include("model_macro.jl")
        include("of_model_integration.jl")
    end,
    "graphs" => () -> include("graphs.jl"),
    "compilation" => () -> begin
        include("model/utils.jl")
        include("model/bugsmodel.jl")
        include("source_gen.jl")
    end,
    "model_operations" => () -> begin
        include("model/abstractppl.jl")
    end,
    "log_density" => () -> begin
        include("model/evaluation.jl")
    end,
    "inference" => () -> begin
        include("independent_mh.jl")
        include("ext/JuliaBUGSAdvancedHMCExt.jl")
        include("ext/JuliaBUGSMCMCChainsExt.jl")
    end,
    "inference_hmc" => () -> include("ext/JuliaBUGSAdvancedHMCExt.jl"),
    "inference_chains" => () -> include("ext/JuliaBUGSMCMCChainsExt.jl"),
    "inference_mh" => () -> include("independent_mh.jl"),
    "gibbs" => () -> include("gibbs.jl"),
    "parallel_sampling" => () -> include("parallel_sampling.jl"),
    "experimental" => () -> 1, # TODO: revive this
    # () -> include("experimental/ProbabilisticGraphicalModels/bayesnet.jl"),
)

raw_selection = get(ENV, "TEST_GROUP", "all")
selected_groups = Set(split(raw_selection, ','))

if "all" ∉ selected_groups
    unknown = setdiff(selected_groups, keys(TEST_GROUPS))
    if !isempty(unknown)
        error("Unknown test group(s): $(join(collect(unknown), ", "))")
    end
end

# Execute the requested tests.
if "all" in selected_groups
    @info "Running tests for ALL groups"
    for fn in values(TEST_GROUPS)
        fn()
    end
else
    @info "Running tests for groups: $(join(collect(selected_groups), ", "))"
    for g in selected_groups
        TEST_GROUPS[g]()
    end
end
