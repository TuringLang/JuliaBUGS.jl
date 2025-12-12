using Documenter
using JuliaBUGS
using MetaGraphsNext
using JuliaBUGS.BUGSPrimitives

makedocs(;
    sitename="JuliaBUGS.jl",
    warnonly=[:cross_references, :doctest],
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
        "API Reference" => [
            "General" => "api/api.md",
            "Functions" => "api/functions.md",
            "Distributions" => "api/distributions.md",
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
        ],
    ],
)
