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
#     julia --project=. gen_bundles.jl out/          # write model, data, and run.sh
#     julia --project=. gen_bundles.jl out/ rats     # or just one example
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

length(ARGS) >= 1 || error("usage: gen_bundles.jl <out-dir> [example-key]")
const OUT = abspath(ARGS[1])
const ONLY = length(ARGS) >= 2 ? Symbol(ARGS[2]) : nothing

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
        println(io, "\"\"\")")
        println(io)
        println(io, "build_model(data) = JuliaBUGS.compile(model_def, data)")
    end

    open(joinpath(dir, "$(key).data.json"), "w") do io
        JSON.print(io, Dict(string(k) => jsonable(v) for (k, v) in pairs(ex.data)))
    end
end

function main()
    mkpath(OUT)
    written = Symbol[]

    for (vol, examples) in pairs(BE.volumes()), (key, ex) in pairs(examples)
        ONLY === nothing || key === ONLY || continue
        write_example(OUT, vol, key, ex)
        push!(written, key)
    end

    isempty(written) && error("no example matched $(ONLY)")

    open(joinpath(OUT, "run.sh"), "w") do io
        println(io, "#!/bin/sh")
        println(
            io, "# Fits every emitted example and exports one bundle each. Slow: hours for"
        )
        println(io, "# the full set. Re-running skips a fit whose inputs have not changed.")
        println(io, "set -e")
        println(io, "cd \"\$(dirname \"\$0\")\"")
        println(io)
        for key in written
            println(io, "echo \"== $key\"")
            println(
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
            println(io, "mcmc export bundle -o bundles/$key.json --force")
            println(io)
        end
    end
    mkpath(joinpath(OUT, "bundles"))

    println("wrote ", length(written), " example(s) to ", OUT)
    println("  fit them with: sh ", joinpath(OUT, "run.sh"))
end

main()
