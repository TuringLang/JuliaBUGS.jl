#!/usr/bin/env julia
#
# Generates one Markdown page per registered example for the volumes that do not
# have hand-written pages yet, plus a per-volume index.
#
# The pages deliberately hold no copy of the model, data, or initial values: they
# pull those from `JuliaBUGS.BUGSExamples` at build time so there is exactly one
# source of truth. Prose is the part a human adds afterwards, in the marked block
# near the top of each page, and this script never overwrites a page that already
# has prose (it skips any file whose PROSE marker has been filled in).
#
# Run from the docs directory:  julia --project=. gen_examples.jl

using JuliaBUGS

const BE = JuliaBUGS.BUGSExamples
const SRC = joinpath(@__DIR__, "src", "examples")

# Volume 1 pages are hand-written and must never be clobbered.
const GENERATE = (:volume_2, :volume_3)

const VOLUME_LABEL = Dict(
    :volume_1 => "Volume 1",
    :volume_2 => "Volume 2",
    :volume_3 => "Volume 3",
    :volume_4 => "Volume 4",
)
const VOLUME_CONST = Dict(
    :volume_1 => "VOLUME_1",
    :volume_2 => "VOLUME_2",
    :volume_3 => "VOLUME_3",
    :volume_4 => "VOLUME_4",
)
const VOLUME_UPSTREAM = Dict(
    :volume_1 => "https://www.multibugs.org/examples/latest/VolumeI.html",
    :volume_2 => "https://www.multibugs.org/examples/latest/VolumeII.html",
    :volume_3 => "https://www.multibugs.org/examples/latest/VolumeIII.html",
    :volume_4 => "https://www.multibugs.org/examples/latest/VolumeIV.html",
)

# Examples whose graph ships inside the doodleppl npm package, keyed by the
# widget's own model name. Anything absent here renders without a graph.
const BUNDLED_GRAPHS = Dict{Symbol,String}(
    :rats => "rats",
    :pumps => "pumps",
    :seeds => "seeds",
    :dyes => "dyes",
    :epil => "epil",
    :equiv => "equiv",
    :kidney => "kidney",
    :mice => "mice",
    :oxford => "oxford",
    :salm => "salm",
    :blockers => "blockers",
    :surgical_realistic => "surgical",
)

"The title line for a page: the example's own name, tidied up."
function page_title(ex)
    t = strip(ex.name)
    endswith(t, ")") && occursin("(", t) || return t
    return t
end

"A stable anchor name for Documenter `@example` blocks."
block_name(vol, key) = string(vol, "_", key)

function graph_section(key::Symbol)
    haskey(BUNDLED_GRAPHS, key) || return ""
    model = BUNDLED_GRAPHS[key]
    return """
## Graph

The directed graph below is live: drag a node to rearrange it, or use the pencil to
edit the model and watch the generated BUGS change.

```@raw html
<div class="doodleppl-embed">
  <doodle-ppl model="$model" height="560px"></doodle-ppl>
  <div class="doodleppl-fallback">
    The interactive graph could not be loaded, which usually means this page is being
    read offline. The model definition above is the authoritative version.
  </div>
</div>
```

"""
end

function render_page(vol::Symbol, key::Symbol, ex, cerr)
    blk = block_name(vol, key)
    vconst = VOLUME_CONST[vol]
    accessor = "JuliaBUGS.BUGSExamples.$vconst.$key"
    hasref = ex.reference_results !== nothing

    io = IOBuffer()
    println(io, "# ", page_title(ex))
    println(io)
    println(
        io,
        "<!-- PROSE: replace this line with a description of the model and its data. -->",
    )
    println(
        io,
        "This example is part of ",
        VOLUME_LABEL[vol],
        " of the classic BUGS examples; the original write-up is on the [MultiBUGS examples page](",
        VOLUME_UPSTREAM[vol],
        ").",
    )
    println(io)
    println(
        io,
        "The model definition, data, initial values",
        hasref ? ", and published reference results" : "",
        " shown here all come from `",
        accessor,
        "`, which ships with the package.",
    )
    println(io)

    println(io, "## Model")
    println(io)
    println(io, "```@example ", blk)
    println(io, "using JuliaBUGS")
    println(io)
    println(io, "example = ", accessor)
    println(io, "example.model_def")
    println(io, "```")
    println(io)

    println(io, "The program as it appears in the original BUGS distribution:")
    println(io)
    println(io, "```@example ", blk)
    println(io, "print(example.original_syntax_program)")
    println(io, "```")
    println(io)

    print(io, graph_section(key))

    println(io, "## Data")
    println(io)
    println(io, "```@example ", blk)
    println(io, "example.data")
    println(io, "```")
    println(io)

    println(io, "## Compiling the model")
    println(io)
    if cerr === nothing
        println(io, "```@example ", blk)
        println(io, "model = JuliaBUGS.compile(example.model_def, example.data)")
        println(io, "```")
        println(io)
        println(
            io,
            "Initial values for the sampler are bundled too, as `example.inits`",
            " (a second set is available as `example.inits_alternative`).",
        )
    else
        println(io, "!!! warning \"Not yet supported\"")
        println(io, "    JuliaBUGS cannot compile this model yet:")
        println(io, "    `", cerr, "`.")
        println(io, "    The model definition and data above are correct and ship with the")
        println(
            io, "    package; only the compile step below is blocked. The block is shown"
        )
        println(io, "    but not executed.")
        println(io)
        println(io, "```julia")
        println(io, "model = JuliaBUGS.compile(example.model_def, example.data)")
        println(io, "```")
    end
    println(io)

    cerr === nothing || return String(take!(io))

    println(io, "## Sampling")
    println(io)
    println(io, "This block is not executed when the documentation is built, so that the")
    println(io, "build stays fast; run it locally to reproduce the numbers below.")
    println(io)
    println(io, "```julia")
    println(
        io,
        "using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, MCMCChains, LogDensityProblems",
    )
    println(io)
    println(io, "model = JuliaBUGS.compile(example.model_def, example.data)")
    println(io, "model = JuliaBUGS.initialize!(model, example.inits)")
    println(
        io,
        "ad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake(; config=nothing))",
    )
    println(io)
    println(io, "n_samples, n_adapts = 2000, 1000")
    println(io, "chain = AbstractMCMC.sample(")
    println(io, "    ad_model, NUTS(0.8), n_samples;")
    println(io, "    chain_type=Chains, n_adapts=n_adapts, discard_initial=n_adapts,")
    println(io, ")")
    println(io, "summarystats(chain)")
    println(io, "```")
    println(io)

    if hasref
        println(io, "## Reference results")
        println(io)
        println(
            io, "The posterior summaries published with the original example. A converged"
        )
        println(io, "chain should reproduce these up to Monte Carlo error.")
        println(io)
        println(io, "```@example ", blk)
        println(io, "example.reference_results")
        println(io, "```")
        println(io)
    end

    return String(take!(io))
end

"""
Try to compile an example, returning `nothing` on success or the error message.
Some examples in the registry use language features JuliaBUGS does not support
yet; their pages show the model but do not execute a compile block.
"""
function compile_error(ex)
    try
        JuliaBUGS.compile(ex.model_def, ex.data)
        return nothing
    catch e
        return first(split(sprint(showerror, e), "\n"), 1)[1]
    end
end

"True when a page still carries the untouched PROSE marker."
is_generated(path) = isfile(path) && occursin("<!-- PROSE:", read(path, String))

function main()
    mkpath(SRC)
    written, skipped = String[], String[]
    vols = BE.volumes()

    for vol in GENERATE
        haskey(vols, vol) || continue
        dir = joinpath(SRC, string(vol))
        mkpath(dir)
        for (key, ex) in pairs(vols[vol])
            path = joinpath(dir, string(key, ".md"))
            if isfile(path) && !is_generated(path)
                push!(skipped, relpath(path, SRC))
                continue
            end
            write(path, render_page(vol, key, ex, compile_error(ex)))
            push!(written, relpath(path, SRC))
        end

        # Per-volume index.
        io = IOBuffer()
        println(io, "# ", VOLUME_LABEL[vol])
        println(io)
        println(
            io,
            "The ",
            VOLUME_LABEL[vol],
            " examples that JuliaBUGS can currently compile. ",
            "The original write-ups are on the [MultiBUGS examples page](",
            VOLUME_UPSTREAM[vol],
            ").",
        )
        println(io)
        println(
            io,
            "Every example on these pages is available in the package as ",
            "`JuliaBUGS.BUGSExamples.",
            VOLUME_CONST[vol],
            ".<key>`.",
        )
        println(io)
        println(io, "| Example | Key | Model |")
        println(io, "|---|---|---|")
        for (key, ex) in pairs(vols[vol])
            println(
                io, "| [", page_title(ex), "](", key, ".md) | `", key, "` | ", ex.name, " |"
            )
        end
        idx = joinpath(dir, "index.md")
        write(idx, String(take!(io)))
        push!(written, relpath(idx, SRC))
    end

    println("wrote ", length(written), " pages")
    foreach(p -> println("  + ", p), written)
    if !isempty(skipped)
        println("\nskipped ", length(skipped), " pages that already have prose")
        foreach(p -> println("  = ", p), skipped)
    end
end

main()
