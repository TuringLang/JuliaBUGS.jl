using Documenter
using JuliaBUGS
using MetaGraphsNext
using JuliaBUGS.BUGSPrimitives

makedocs(;
    sitename="JuliaBUGS.jl",
    pages=[
        "Home" => "index.md",
        "Example" => "example.md",
        "API" => [
            "General" => "api/api.md",
            "Functions" => "api/functions.md",
            "Distributions" => "api/distributions.md",
            "User-Defined Functions and Distributions" => "api/user_defined_functions.md",
        ],
        "Differences from Other BUGS Implementations" => "differences.md",
        "Pitfalls" => "pitfalls.md",
        "Plotting" => "graph_plotting.md",
        "R Interface" => "R_interface.md",
        "For Developers" =>
            ["Parser" => "parser.md", "Notes on BUGS Implementations" => "BUGS_notes.md"],
    ],
)
