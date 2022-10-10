using Documenter, SymbolicPPL

About = "Introduction" => "index.md"

Compiler = "Compiler Design" => [
        "compiler.md",
    ]

AST = "Julia AST for BUGS" => [
        "ast.md"
    ]

GraphInfo = "Graphical Representation of Probabilistic Programs" => [
        "graphinfo.md"
    ]

Examples = "Examples" => [
        "example.md"
    ]

PAGES = [
    About,
    Compiler,
    AST,
    GraphInfo,
    Examples
]

makedocs(
    sitename = "Augmentor.jl",
)
