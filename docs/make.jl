using Documenter, SymbolicPPL

makedocs(
    sitename = "SymbolicPPL.jl",
    pages = [
        "Introduction" => "index.md",
        "AST Transformation" => "ast.md",
        "Example" => "example.md",
        "API" => "api.md",
    ]
)


