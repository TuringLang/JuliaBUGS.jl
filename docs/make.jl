using Documenter
using JuliaBUGS
using JuliaBUGS: compile, BUGSModel
using JuliaBUGS.BUGSPrimitives

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
