using Documenter
using JuliaBUGS
using JuliaBUGS: @bugs, compile, BUGSModel, BUGSGraph
using MetaGraphsNext
using JuliaBUGS.BUGSPrimitives
using DynamicPPL: SimpleVarInfo

makedocs(;
    sitename="JuliaBUGS.jl",
    pages=[
        "Introduction" => "index.md",
        "Example" => "example.md",
        "API" => [
            "General" => "api.md",
            "Functions" => "functions.md",
            "Distributions" => "distributions.md",
            "User-defined Functions and Distributions" => "user_defined_functions.md",
        ],
        "Plotting" => "graph_plotting.md",
        "R Interface" => "R_interface.md",
        "Pitfalls" => "pitfalls.md",
        "For Developers" =>
            ["Parser" => "parser.md", "Notes on BUGS Implementations" => "BUGS_notes.md"],
        "Examples" => "BUGSExamples.md"
    ],
)

deploydocs(; repo="github.com/TuringLang/JuliaBUGS.jl.git", push_preview=true)
