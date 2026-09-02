#!/usr/bin/env julia
#
# Writes each registered example out as a model file, a data file, and a shell script
# that fits it with the mcmcjs CLI and exports one self-contained run bundle per
# example. The bundles can then be hosted anywhere and opened in the report app at
# https://mcmcjs.github.io/report/#bundle=<url>.
#
# This script itself has no dependency on mcmcjs: it only writes files. Fitting all
# of the examples takes hours, so it is deliberately a two-step process, run by hand:
#
#     julia --project=. gen_bundles.jl out/            # every volume
#     julia --project=. gen_bundles.jl out/ volume_1   # one volume
#     julia --project=. gen_bundles.jl out/ rats       # one example
#     sh out/run.sh                                  # fit and export (slow)
#
# Sampler settings follow what the OpenBUGS documentation reports for these examples,
# "a 1000 update burn in followed by a further 10000 updates", over the two chains its
# two sets of initial values imply. `--thin 10` keeps 1000 of those 10000 draws, which
# is what holds a bundle under the size the report app will fetch; the sampling effort
# is unchanged. Note that JuliaBUGS samples with NUTS where OpenBUGS used Gibbs, so
# posterior means should agree but Monte Carlo error will not.

using JuliaBUGS, JSON

const BE = JuliaBUGS.BUGSExamples

const CHAINS = 2
const WARMUP = 1000
const UPDATES = 10_000
const KEEP = 1000

length(ARGS) >= 1 ||
    error("usage: gen_bundles.jl <out-dir> [volume_1|volume_2|volume_3|all|<example-key>]")
const OUT = abspath(ARGS[1])

# The second argument selects either a whole volume or a single example. Fitting
# everything takes hours, so a volume at a time is the usual way to run this.
const SELECT = length(ARGS) >= 2 && !isempty(ARGS[2]) ? Symbol(ARGS[2]) : :all
const VOLUMES = (:volume_1, :volume_2, :volume_3)
const WANT_VOL = if SELECT === :all
    VOLUMES
elseif SELECT in VOLUMES
    (SELECT,)
else
    VOLUMES
end
const WANT_KEY = SELECT === :all || SELECT in VOLUMES ? nothing : SELECT

"""
The driver rebuilds matrices with `stack(elems; dims = 1)`, so every inner JSON array
has to be a row. Julia's `JSON.print` writes a matrix column-wise, which arrives
transposed and then fails on the first out-of-range index, so rows are split here.
"""
jsonable(v::AbstractMatrix) = [collect(v[i, :]) for i in 1:size(v, 1)]
jsonable(v::AbstractArray{T,3}) where {T} = [jsonable(v[i, :, :]) for i in 1:size(v, 1)]
jsonable(v) = v

"""
    write_example(dir, vol, key, ex)

Write `<key>.jl` and `<key>.data.json`. The model file carries the original BUGS
program verbatim and parses it with the string form of `@bugs`, so what gets fitted is
the program a reader recognises rather than a deparsed Julia AST.
"""
function write_example(dir, vol, key, ex)
    open(joinpath(dir, "$(key).jl"), "w") do io
        println(io, "# ", ex.name)
        println(
            io, "# Generated from JuliaBUGS.BUGSExamples.", uppercase(string(vol)), ".", key
        )
        println(io, "using JuliaBUGS")
        println(io)
        println(io, "model_def = JuliaBUGS.@bugs(\"\"\"")
        print(io, ex.original_syntax_program)
        # `false` keeps the dotted BUGS names, so a published parameter reads
        # `beta.c` exactly as the original program and its reference table do.
        println(io, "\"\"\", false)")
        println(io)
        println(io, "build_model(data) = JuliaBUGS.compile(model_def, data)")
    end

    open(joinpath(dir, "$(key).data.json"), "w") do io
        JSON.print(io, Dict(string(k) => jsonable(v) for (k, v) in pairs(ex.data)))
    end
end

"""
    plotted_variables(ex)

Which variables the published plots should show. A trace panel per parameter is
unreadable once a model has dozens, and Rats alone has 65, so this picks the ones
a reader came for: the parameters the original example published summaries for,
or failing that the scalars, which are the population-level quantities in these
models rather than the per-unit ones.
"""
function plotted_variables(ex; limit=6)
    published = ex.reference_results
    if !isnothing(published) && !isempty(published)
        return first(String.(collect(keys(published))), limit)
    end
    scalars = [String(k) for (k, v) in pairs(ex.inits) if v isa Number]
    return first(sort(scalars), limit)
end

function main()
    mkpath(OUT)
    written = Pair{Symbol,Vector{String}}[]

    for (vol, examples) in pairs(BE.volumes()), (key, ex) in pairs(examples)
        vol in WANT_VOL || continue
        WANT_KEY === nothing || key === WANT_KEY || continue
        write_example(OUT, vol, key, ex)
        push!(written, key => plotted_variables(ex))
    end

    isempty(written) && error("nothing matched $(SELECT)")

    open(joinpath(OUT, "run.sh"), "w") do io
        println(io, "#!/bin/sh")
        println(
            io, "# Fits every emitted example and exports one bundle each. Slow: hours for"
        )
        println(io, "# the full set. Re-running skips a fit whose inputs have not changed.")
        println(io, "#")
        println(io, "# A model that fails is reported and skipped rather than stopping the")
        println(io, "# sweep, because losing an hour of finished fits to one bad model is")
        println(io, "# worse than an incomplete set. The exit status counts the failures.")
        println(io, "cd \"\$(dirname \"\$0\")\"")
        println(io, "failed=0")
        println(io)
        for (key, vars) in written
            shown = isempty(vars) ? "" : " --var " * join(("'$v'" for v in vars), " ")
            println(io, "echo \"== $key\"")
            print(
                io,
                "mcmc run $key.jl --data $key.data.json",
                " --chains ",
                CHAINS,
                " --warmup ",
                WARMUP,
                " --draws ",
                KEEP,
                " --thin ",
                UPDATES ÷ KEEP,
                " --seed 42",
            )
            println(io, " \\")
            println(io, "  && mcmc export bundle -o bundles/$key.json --force \\")
            println(
                io,
                "  && mcmc plot --kind trace$shown --format svg",
                " -o bundles/$key-trace.svg \\",
            )
            println(
                io,
                "  && mcmc plot --kind density$shown --format svg",
                " -o bundles/$key-density.svg \\",
            )
            println(io, "  || { echo \"   $key FAILED\"; failed=\$((failed + 1)); }")
            println(io)
        end
        println(io, "echo \"\$failed example(s) failed\"")
        println(io, "exit \$failed")
    end
    mkpath(joinpath(OUT, "bundles"))

    println("wrote ", length(written), " example(s) to ", OUT)
    println("  fit them with: sh ", joinpath(OUT, "run.sh"))
end

main()
