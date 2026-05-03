using BUGSExamples
using Documenter
using Literate

# --- Generate markdown from Literate.jl source files ---

const EXAMPLES_SRC = joinpath(@__DIR__, "..", "src")
const GENERATED_DIR = joinpath(@__DIR__, "src", "generated")

# Process each volume directory
generated_pages = Dict{String,Vector{Pair{String,String}}}()

for vol in ["Volume_1", "Volume_2"]
    vol_src = joinpath(EXAMPLES_SRC, vol)
    isdir(vol_src) || continue

    vol_out = joinpath(GENERATED_DIR, vol)
    mkpath(vol_out)

    pages = Pair{String,String}[]
    for file in sort(filter(f -> endswith(f, ".jl"), readdir(vol_src)))
        Literate.markdown(
            joinpath(vol_src, file),
            vol_out;
            codefence = "```julia" => "```",  # Don't execute code in Documenter
            credit = false,
        )
        # Convert filename to a nice page title: "01_Rats.jl" → "Rats"
        page_name = replace(splitext(file)[1], r"^\d+_" => "")
        page_name = replace(page_name, "_" => " ")
        md_file = replace(file, ".jl" => ".md")
        push!(pages, page_name => joinpath("generated", vol, md_file))
    end
    generated_pages[vol] = pages
end

# --- Build documentation ---

DocMeta.setdocmeta!(BUGSExamples, :DocTestSetup, :(using BUGSExamples); recursive=true)

# Assemble pages list
page_list = Any["Home" => "index.md"]

if haskey(generated_pages, "Volume_1") && !isempty(generated_pages["Volume_1"])
    push!(page_list, "Volume 1" => generated_pages["Volume_1"])
end
if haskey(generated_pages, "Volume_2") && !isempty(generated_pages["Volume_2"])
    push!(page_list, "Volume 2" => generated_pages["Volume_2"])
end

push!(page_list, "API Reference" => "api.md")

makedocs(;
    modules=[BUGSExamples],
    authors="Shravan Goswami <shravanngoswamii@gmail.com> and contributors, Xianda Sun and contributors",
    sitename="BUGSExamples.jl",
    format=Documenter.HTML(;
        canonical="https://TuringLang.github.io/JuliaBUGS.jl/BUGSExamples",
        edit_link="main",
        assets=String[],
    ),
    pages=page_list,
)

deploydocs(;
    repo="github.com/TuringLang/JuliaBUGS.jl",
    devbranch="main",
    dirname="BUGSExamples",
    push_preview=true,
)
