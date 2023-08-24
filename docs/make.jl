using Documenter
using JuliaBUGS
using JuliaBUGS: @bugs, compile, BUGSModel, BUGSGraph, ConcreteNodeInfo
using MetaGraphsNext
using JuliaBUGS.BUGSPrimitives
using DynamicPPL: SimpleVarInfo

makedocs(;
    sitename="JuliaBUGS.jl",
    pages=[
        "Introduction" => "index.md",
        "API" => [
            "General" => "api.md",
            "Functions" => "functions.md",
            "Distributions" => "distributions.md",
        ],
        "Plotting" => "graph_plotting.md",
        "R Interface" => "R_interface.md",
        "Pitfalls" => "pitfalls.md",
        "For Developers" => ["Parser" => "parser.md"],
    ],
)

deploydocs(; repo="github.com/TuringLang/JuliaBUGS.jl.git")
