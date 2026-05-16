using BUGSExamples
using Documenter
using DocumenterCitations
using DocumenterVitepress

include(joinpath(@__DIR__, "build_pages.jl"))

const GENERATED_DIR = joinpath(@__DIR__, "src", "generated")
example_pages = build_pages(GENERATED_DIR)

bib = CitationBibliography(joinpath(@__DIR__, "src", "refs.bib"); style = :numeric)

DocMeta.setdocmeta!(BUGSExamples, :DocTestSetup, :(using BUGSExamples); recursive=true)

pages = Any["Home" => "index.md"]
isempty(example_pages) || push!(pages, "Examples" => example_pages)
push!(pages, "API Reference" => "api.md")
push!(pages, "Bibliography" => "bibliography.md")

makedocs(;
    modules=[BUGSExamples],
    warnonly=[:missing_docs, :cross_references],
    authors="Shravan Goswami <shravanngoswamii@gmail.com>, Xianda Sun",
    sitename="BUGSExamples.jl",
    format=DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/TuringLang/JuliaBUGS.jl",
        devbranch = "main",
        devurl = "dev",
    ),
    pages=pages,
    plugins=[bib],
)

DocumenterVitepress.deploydocs(;
    repo = "github.com/TuringLang/JuliaBUGS.jl",
    target = joinpath(@__DIR__, "build"),
    branch = "gh-pages",
    devbranch = "main",
    dirname = "BUGSExamples",
    push_preview = true,
)
