#!/usr/bin/env julia
#
# Generates the Volume 2 and Volume 3 example pages, plus a per-volume index.
#
# The pages hold no copy of the model, data, or initial values: they pull those from
# `JuliaBUGS.BUGSExamples` at build time, so there is one source of truth and a page
# cannot drift from the registry.
#
# Prose is written by hand, above the `## Model` heading. A page is regenerated only
# while it still carries the `<!-- PROSE:` marker, so once prose is written the script
# leaves that page alone; to refresh the mechanical part of a page that already has
# prose, keep everything above `## Model` and replace the rest.
#
# Nothing runs this automatically. It is a maintenance script, invoked by hand when the
# registry changes:
#
#     julia --project=. gen_examples.jl

using JuliaBUGS

const BE = JuliaBUGS.BUGSExamples
const SRC = joinpath(@__DIR__, "src", "examples")

# Volume 1 pages are hand-written and must never be clobbered.
const GENERATE = (:volume_2, :volume_3)

const VOLUME_LABEL = Dict(:volume_2 => "Volume 2", :volume_3 => "Volume 3")
const VOLUME_CONST = Dict(:volume_2 => "VOLUME_2", :volume_3 => "VOLUME_3")
const VOLUME_UPSTREAM = Dict(
    :volume_2 => "https://www.multibugs.org/examples/latest/VolumeII.html",
    :volume_3 => "https://www.multibugs.org/examples/latest/VolumeIII.html",
)

"A stable anchor name for Documenter `@example` blocks."
block_name(vol, key) = string(vol, "_", key)

"Whether a field carries anything worth rendering a section for."
present(x) = !isnothing(x) && !isempty(x)

"""
    compile_plan(ex)

Decide how an example's page should compile it, by trying each way several times and
taking the first that never fails.

Two failure modes make a single attempt useless. Some models throw a `DomainError` from
random starting values and succeed from the example's own initial values: `endo`,
`alligators`, and the Volume 1 survival models are all in this group, which is why the
hand-written pages have always passed inits. Others go the other way, notably `biopsies`,
whose initial values leave `missing` in the upper triangle of `error`, which `Multinomial`
rejects, even though it compiles happily without them.

Returns `(; call, error, uses_inits)`. `call` is the Julia source the page should show,
and `error` is `nothing` when that call is reliable, or the message when neither way works.
"""
function compile_plan(ex)
    # Repeats catch the models that fail only from some random starting values. The time
    # budget keeps the big ones honest: hips2 has 720 parameters, and eight compiles of it
    # cost more than the check is worth.
    attempts = 8
    budget_seconds = 20.0
    bare = "model = JuliaBUGS.compile(example.model_def, example.data)"
    with_inits = "model = JuliaBUGS.compile(example.model_def, example.data, example.inits)"

    function probe(f)
        started = time()
        for _ in 1:attempts
            try
                f()
            catch e
                return first(split(sprint(showerror, e), "\n"))
            end
            time() - started > budget_seconds && break
        end
        return nothing
    end

    if present(ex.inits)
        if probe(() -> JuliaBUGS.compile(ex.model_def, ex.data, ex.inits)) === nothing
            return (; call=with_inits, error=nothing, uses_inits=true)
        end
    end

    err = probe(() -> JuliaBUGS.compile(ex.model_def, ex.data))
    return (; call=bare, error=err, uses_inits=false)
end

function render_page(vol::Symbol, key::Symbol, ex, plan)
    blk = block_name(vol, key)
    accessor = "JuliaBUGS.BUGSExamples.$(VOLUME_CONST[vol]).$key"
    hasref = present(ex.reference_results)
    hasdata = present(ex.data)

    io = IOBuffer()
    println(io, "# ", strip(ex.name))
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
        "The model definition",
        hasdata ? ", data" : "",
        ", initial values",
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

    if hasdata
        println(io, "## Data")
        println(io)
        println(io, "```@example ", blk)
        println(io, "example.data")
        println(io, "```")
        println(io)
    end

    println(io, "## Compiling the model")
    println(io)
    if plan.error === nothing
        println(io, "```@example ", blk)
        println(io, plan.call)
        println(io, "```")
        println(io)
        if plan.uses_inits
            println(
                io,
                "The example's own initial values are passed in here. Several of these",
                " models fail from random starting values, so `example.inits` is not",
                " optional in practice; a second set is available as",
                " `example.inits_alternative`.",
            )
            println(io)
        end
    else
        println(io, "!!! warning \"Does not compile\"")
        println(io, "    JuliaBUGS cannot compile this model: `", plan.error, "`.")
        println(io, "    The model and data above are correct and ship with the package;")
        println(io, "    only the compile step is blocked, so it is shown but not run.")
        println(io)
        println(io, "```julia")
        println(io, plan.call)
        println(io, "```")
        println(io)
    end

    println(
        io,
        "See [Getting Started](../../getting_started.md) for the recipe that takes a",
        " compiled model to posterior samples.",
    )
    println(io)

    if hasref
        println(io, "## Reference results")
        println(io)
        println(io, "The posterior summaries published with the original example. A")
        println(io, "converged chain should reproduce these up to Monte Carlo error.")
        println(io)
        println(io, "```@example ", blk)
        println(io, "example.reference_results")
        println(io, "```")
    end

    return rstrip(String(take!(io))) * "\n"
end

"True while a page still carries the untouched PROSE marker."
is_generated(path) = isfile(path) && occursin("<!-- PROSE:", read(path, String))

function render_index(vol::Symbol, examples)
    io = IOBuffer()
    println(io, "# ", VOLUME_LABEL[vol])
    println(io)
    println(
        io,
        "The ",
        VOLUME_LABEL[vol],
        " examples that JuliaBUGS can currently compile. The original write-ups are on",
        " the [MultiBUGS examples page](",
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
    println(io, "| Example | Key |")
    println(io, "|---|---|")
    for (key, ex) in pairs(examples)
        println(io, "| [", strip(ex.name), "](", key, ".md) | `", key, "` |")
    end
    return rstrip(String(take!(io))) * "\n"
end

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
            write(path, render_page(vol, key, ex, compile_plan(ex)))
            push!(written, relpath(path, SRC))
        end

        idx = joinpath(dir, "index.md")
        write(idx, render_index(vol, vols[vol]))
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
