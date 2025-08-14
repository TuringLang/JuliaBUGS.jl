using Documenter
using JuliaBUGS
using MetaGraphsNext
using JuliaBUGS.BUGSPrimitives

makedocs(;
    sitename="JuliaBUGS.jl",
    pages=[
        "Home" => "index.md",
        "Example" => "example.md",
        "Modeling" => [
            "Two Macros: `@bugs` & `@model`" => "two_macros.md",
            "`@model` Macro" => "model_macro.md",
            "`of` Type System" => "of_design_doc.md",
        ],
        "API" => [
            "General" => "api/api.md",
            "Functions" => "api/functions.md",
            "Distributions" => "api/distributions.md",
        ],
        "Differences from Other BUGS Implementations" => "differences.md",
        "Pitfalls" => "pitfalls.md",
        "Plotting" => "graph_plotting.md",
        "R Interface" => "R_interface.md",
        "For Developers" => [
            "Parser" => "parser.md",
            "Source Code Generation" => "source_gen.md",
            "Implementation Tricks" => "tricks.md",
            "Notes on BUGS Implementations" => "BUGS_notes.md",
        ],
    ],
)
