using Documenter
using SymbolicPPL

makedocs(;
    sitename="SymbolicPPL.jl",
    pages=[
        "Introduction" => "index.md",
        "BUGS Language Reference" => "bugs_lang.md",
        "API" => "api.md",
        "AST Translation" => "ast.md",
        "Array Interface" => "array.md",
        "Compilation Target" => "compilation_target.md",
    ],
)

deploydocs(; repo="github.com/TuringLang/SymbolicPPL.jl.git")
