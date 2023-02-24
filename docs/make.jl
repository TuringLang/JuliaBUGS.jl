using Documenter
using JuliaBUGS

makedocs(;
    sitename="JuliaBUGS.jl",
    pages=[
        "Introduction" => "index.md",
        "BUGS Language Reference" => "bugs_lang.md",
        "API" => "api.md",
        "AST Translation" => "ast.md",
        "Array Interface" => "array.md",
        "Compilation Target" => "compilation_target.md",
    ],
)

deploydocs(; repo="github.com/TuringLang/JuliaBUGS.jl.git")
