#!/usr/bin/env julia
using Pkg
using Printf

root = normpath(joinpath(@__DIR__, "..", "..", ".."))
jbugs = joinpath(root, "JuliaBUGS")
@printf "Developing JuliaBUGS from %s\n" jbugs
Pkg.develop(path=jbugs)
Pkg.instantiate()
println("OK")

