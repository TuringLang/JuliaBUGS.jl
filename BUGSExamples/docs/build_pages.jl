using BUGSExamples
using JSON

const TAB_LABELS = (
    "model.jl"     => "JuliaBUGS @bugs",
    "model_fn.jl"  => "JuliaBUGS @model",
    "model.bugs"   => "BUGS",
    "model.stan"   => "Stan",
    "model.py"     => "NumPyro",
)

const FENCE_LANG = Dict(
    "model.bugs"  => "julia",         # BUGS syntax is R-shaped; r highlights it cleanly
    "model.jl"    => "julia",
    "model_fn.jl" => "julia",
    "model.stan"  => "stan",
    "model.py"    => "python",
)

function _render_results_table(io::IO, params::NamedTuple)
    cols = collect(keys(first(values(params))))
    println(io, "| Parameter | ", join(string.(cols), " | "), " |")
    println(io, "|", join(fill("---", length(cols) + 1), "|"), "|")
    for (name, summary) in pairs(params)
        vals = [haskey(summary, c) ? string(getfield(summary, c)) : "—" for c in cols]
        println(io, "| `", string(name), "` | ", join(vals, " | "), " |")
    end
end

function _render_results_meta(io::IO, meta::NamedTuple)
    isempty(meta) && return
    parts = String[]
    haskey(meta, :sampler)            && push!(parts, string("sampler: ", meta.sampler))
    haskey(meta, :n_samples)          && push!(parts, string(meta.n_samples, " samples"))
    haskey(meta, :n_chains)           && push!(parts, string(meta.n_chains, " chains"))
    haskey(meta, :ran_at)             && push!(parts, string("ran ", meta.ran_at))
    haskey(meta, :juliabugs_version)  && push!(parts, string("JuliaBUGS v", meta.juliabugs_version))
    haskey(meta, :note)               && push!(parts, string(meta.note))
    isempty(parts) || println(io, "\n*", join(parts, " · "), "*")
end

function _render_example_page(ex::BUGSExamples.BUGSExample)
    io = IOBuffer()
    title = ex.name
    println(io, "# ", title)
    println(io)

    if !isempty(ex.description)
        println(io, strip(ex.description))
        println(io)
    end

    if ex.doodlebugs_id !== nothing
        println(io, "## Graphical Model")
        println(io)
        println(io, "```@raw html")
        println(io, "<doodle-bugs width=\"100%\" height=\"600px\" model=\"",
                ex.doodlebugs_id, "\"></doodle-bugs>")
        println(io, "```")
        println(io)
    end

    println(io, "## Model")
    println(io)
    available = [(f, label) for (f, label) in TAB_LABELS if isfile(joinpath(ex.source_dir, f))]
    if !isempty(available)
        println(io, "::: tabs")
        println(io)
        for (file, label) in available
            println(io, "== ", label)
            println(io)
            println(io, "```", FENCE_LANG[file])
            print(io, rstrip(read(joinpath(ex.source_dir, file), String)))
            println(io)
            println(io, "```")
            println(io)
        end
        println(io, ":::")
        println(io)
    end

    if ex.sampled_results !== nothing
        println(io, "## Results")
        println(io)
        _render_results_table(io, ex.sampled_results.params)
        _render_results_meta(io, ex.sampled_results.meta)
        println(io)
    end

    if ex.reference_results !== nothing
        println(io, "```@raw html")
        println(io, "<details>")
        println(io, "<summary><strong>Reference values for comparison</strong></summary>")
        println(io, "```")
        println(io)
        _render_results_table(io, ex.reference_results.params)
        _render_results_meta(io, ex.reference_results.meta)
        println(io)
        println(io, "```@raw html")
        println(io, "</details>")
        println(io, "```")
        println(io)
    end

    println(io, "## How to use this example")
    println(io)
    println(io, "```julia")
    println(io, "using JuliaBUGS, BUGSExamples")
    println(io, "ex = BUGSExamples.", basename(ex.source_dir))
    println(io, "model = compile(@bugs(ex.original_syntax_program), ex.data, ex.inits)")
    println(io, "```")
    println(io)

    if !isempty(ex.citations)
        println(io, "## References")
        println(io)
        for key in ex.citations
            println(io, "- [", key, "](@cite)")
        end
        println(io)
    end

    return String(take!(io))
end

"""
    build_pages(output_dir) -> Vector{Pair{String,String}}

Generate one markdown page per registered BUGSExample into `output_dir`,
returning a list of `"Page Title" => relative_path` pairs suitable for use as
a sidebar group in `makedocs(pages=…)`.
"""
function build_pages(output_dir::String)
    mkpath(output_dir)
    pages = Pair{String,String}[]
    for (sym, ex) in pairs(BUGSExamples.examples())
        slug = String(sym)
        md = _render_example_page(ex)
        write(joinpath(output_dir, slug * ".md"), md)
        push!(pages, ex.name => joinpath("generated", slug * ".md"))
    end
    return pages
end
