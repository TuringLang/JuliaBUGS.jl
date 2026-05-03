using BUGSExamples
using Documenter
using Literate

const EXAMPLES_SRC = joinpath(@__DIR__, "..", "src")
const GENERATED_DIR = joinpath(@__DIR__, "src", "generated")

# Find all model directories (each with a model.jl)
model_dirs = String[]
for entry in readdir(EXAMPLES_SRC)
    model_file = joinpath(EXAMPLES_SRC, entry, "model.jl")
    if isdir(joinpath(EXAMPLES_SRC, entry)) && isfile(model_file)
        push!(model_dirs, entry)
    end
end
sort!(model_dirs)

# Generate markdown for each model
generated_pages = Pair{String,String}[]
mkpath(GENERATED_DIR)

for model_name in model_dirs
    model_file = joinpath(EXAMPLES_SRC, model_name, "model.jl")
    Literate.markdown(
        model_file,
        GENERATED_DIR;
        codefence = "```julia" => "```",
        credit = false,
        name = model_name,
    )
    # Title case the model name
    page_title = titlecase(replace(model_name, "_" => " "))
    push!(generated_pages, page_title => joinpath("generated", "$(model_name).md"))
end

# --- Build documentation ---

DocMeta.setdocmeta!(BUGSExamples, :DocTestSetup, :(using BUGSExamples); recursive=true)

page_list = Any[
    "Home" => "index.md",
]

if !isempty(generated_pages)
    push!(page_list, "Examples" => generated_pages)
end

push!(page_list, "API Reference" => "api.md")

makedocs(;
    modules=[BUGSExamples],
    warnonly=[:missing_docs, :cross_references],
    authors="Shravan Goswami <shravanngoswamii@gmail.com>, Xianda Sun",
    sitename="BUGSExamples.jl",
    format=Documenter.HTML(;
        canonical="https://TuringLang.github.io/JuliaBUGS.jl/BUGSExamples",
        edit_link="main",
        assets=[
            asset("https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/pr-previews/451/lib/doodlebugs.css", class=:css),
            asset("https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/pr-previews/451/lib/doodlebugs.js", class=:js, attributes=Dict(:type => "module")),
            asset("assets/sync_theme.js", class=:js),
        ],
    ),
    pages=page_list,
)

deploydocs(;
    repo="github.com/TuringLang/JuliaBUGS.jl",
    devbranch="main",
    dirname="BUGSExamples",
    push_preview=true,
)
