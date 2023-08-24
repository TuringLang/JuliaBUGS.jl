using Documenter
using JuliaBUGS
using JuliaBUGS: compile, BUGSModel, BUGSGraph, ConcreteNodeInfo
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
    ],
)

deploydocs(; repo="github.com/TuringLang/JuliaBUGS.jl.git")
