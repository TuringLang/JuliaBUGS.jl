module BUGSExamples

using SymbolicPPL
using MCMCChains
using MCMCChains: summarize
using StatsPlots

function compile(m::NamedTuple)
    @assert keys(m) == (:name, :model_def, :data, :inits)
    chains = []
    for init in m[:inits]
        push!(chains, compile_graphppl(model_def = m[:model_def], data = m[:data], initials = init))
    end
    return chains
end

row_major_reshape(v::Vector, dim) = permutedims(reshape(v, dim), Tuple(reverse([i for i in 1:length(dim)])))

include("Volume_I/Dogs.jl")
include("Volume_I/Blocker.jl")
include("Volume_I/Equiv.jl")


links = (
    dogs = "https://chjackson.github.io/openbugsdoc/Examples/Dogs.html",
    blocker = "https://chjackson.github.io/openbugsdoc/Examples/Blockers.html",
    equiv = "https://chjackson.github.io/openbugsdoc/Examples/Equiv.html",
)

examples = (
    dogs = dogs,
    blocker = blockers,
    equiv = equiv,

)

export examples

end
