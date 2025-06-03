using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using Documenter
using Test
using JuliaBUGS.BUGSPrimitives: mean
DocMeta.setdocmeta!(JuliaBUGS, :DocTestSetup, :(using JuliaBUGS); recursive=true)

using AbstractPPL
using AbstractMCMC
using AdvancedHMC
using AdvancedMH
using Bijectors
using ChainRules
using DifferentiationInterface
using Distributions
using Graphs
using MetaGraphsNext
using LinearAlgebra
using LogDensityProblems
using LogDensityProblemsAD
using OrderedCollections
using MacroTools
using MCMCChains
using Mooncake: Mooncake
using Random
using ReverseDiff
using Serialization

AbstractMCMC.setprogress!(false)

const TEST_GROUPS = Dict{String,Function}(
    "doctest" => () -> Documenter.doctest(JuliaBUGS; manual=false),
    "model_macro" => () -> include("model_macro.jl"),
    "parser" => () -> include("parser/parser.jl"),
    "compiler_pass" => () -> include("compiler_pass.jl"),
    "graphs" => () -> include("graphs.jl"),
    "source_gen" => () -> include("source_gen.jl"),
    "BUGSPrimitives" => () -> include("BUGSPrimitives/primitives.jl"),
    "evaluation" => () -> include("model/evaluation.jl"),
    "model" => () -> include("model/model.jl"),
    "inference" => () -> include("ext/JuliaBUGSAdvancedHMCExt.jl"),
    # "gibbs" => () -> include("gibbs.jl"),
    # "mcmchains" => () -> include("ext/JuliaBUGSMCMCChainsExt.jl"),
    # "experimental" => () -> include("experimental/ProbabilisticGraphicalModels/bayesnet.jl"),
)

raw_selection = get(ENV, "TEST_GROUP", "all")
selected_groups = Set(split(raw_selection, ','))

if "all" ∉ selected_groups
    unknown = setdiff(selected_groups, keys(TEST_GROUPS))
    if !isempty(unknown)
        error("Unknown test group(s): $(join(collect(unknown), ", "))")
    end
end

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
