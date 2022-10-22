using Documenter 
using SymbolicPPL

makedocs(
    sitename = "SymbolicPPL.jl",
    pages = [
        "Introduction" => "index.md",
        "API" => "api.md",
        "AST Translation" => "ast.md",
    ]
)


