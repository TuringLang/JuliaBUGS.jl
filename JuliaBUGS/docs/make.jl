using Documenter
using DocumenterCitations
using DocumenterVitepress
using JuliaBUGS
using MetaGraphsNext
using JuliaBUGS.BUGSPrimitives
using Distributions
using AbstractPPL
using Test

include(joinpath(@__DIR__, "build_pages.jl"))

const EXAMPLES_OUT_DIR = joinpath(@__DIR__, "src", "examples")
examples_section = build_example_pages(EXAMPLES_OUT_DIR)

bib = CitationBibliography(joinpath(@__DIR__, "src", "refs.bib"); style=:numeric)

DocMeta.setdocmeta!(
    JuliaBUGS,
    :DocTestSetup,
    quote
        using JuliaBUGS, Test, Distributions, AbstractPPL
        using JuliaBUGS.Model: condition, parameters, decondition
        JuliaBUGS.@bugs_primitive Normal Gamma
    end;
    recursive=true,
)

makedocs(;
    sitename="JuliaBUGS.jl",
    modules=[JuliaBUGS],
    authors="The Turing.jl team",
    warnonly=true,
    checkdocs=:exports,
    format=DocumenterVitepress.MarkdownVitepress(;
        repo="github.com/TuringLang/JuliaBUGS.jl", devbranch="main", devurl="dev"
    ),
    pages=[
        "Home" => "index.md",
        "Getting Started" => "example.md",
        "Modeling" => [
            "Two Macros: `@bugs` & `@model`" => "two_macros.md",
            "`@model` Macro" => "model_macro.md",
            "`of` Type System" => "of_design_doc.md",
        ],
        "Inference" => [
            "Automatic Differentiation" => "inference/ad.md",
            "Evaluation Modes" => "inference/evaluation_modes.md",
            "Auto-Marginalization" => "inference/auto_marginalization.md",
            "Parallel & Distributed Sampling" => "inference/parallel.md",
        ],
        examples_section,
        "API Reference" => [
            "General" => "api/api.md",
            "Functions" => "api/functions.md",
            "Distributions" => "api/distributions.md",
            "BUGSExamples" => "api/bugsexamples.md",
        ],
        "Guides" => [
            "Differences from Other BUGS" => "guides/differences.md",
            "Pitfalls" => "guides/pitfalls.md",
            "Implementation Tricks" => "guides/tricks.md",
        ],
        "Plotting" => "graph_plotting.md",
        "R Interface" => "R_interface.md",
        "For Developers" => [
            "Parser" => "developers/parser.md",
            "Source Code Generation" => "developers/source_gen.md",
            "Notes on BUGS Implementations" => "developers/BUGS_notes.md",
            "Internal API" => "developers/internal_api.md",
        ],
        "Bibliography" => "bibliography.md",
    ],
    plugins=[bib],
)

DocumenterVitepress.deploydocs(;
    repo="github.com/TuringLang/JuliaBUGS.jl",
    target=joinpath(@__DIR__, "build"),
    branch="gh-pages",
    devbranch="main",
    push_preview=true,
)
