module BUGSExamples

using JuliaBUGS: @bugs

include("Volume_1/Blocker.jl")
include("Volume_1/Bones.jl")
include("Volume_1/Dogs.jl")
include("Volume_1/Dyes.jl")
include("Volume_1/Epil.jl")
include("Volume_1/Equiv.jl")
include("Volume_1/Inhalers.jl")
include("Volume_1/Kidney.jl")
include("Volume_1/Leuk.jl")
include("Volume_1/LeukFr.jl")
include("Volume_1/LSAT.jl")
include("Volume_1/Magnesium.jl")
include("Volume_1/Mice.jl")
include("Volume_1/Oxford.jl")
include("Volume_1/Pumps.jl")
include("Volume_1/Rats.jl")
include("Volume_1/Salm.jl")
include("Volume_1/Seeds.jl")
include("Volume_1/Stacks.jl")
include("Volume_1/Surgical.jl")

include("Volume_2/BiRats.jl")
include("Volume_2/Eyes.jl")

const VOLUME_1 = (
    blockers=blockers,
    bones=bones,
    dogs=dogs,
    dyes=dyes,
    epil=epil,
    equiv=equiv,
    inhalers=inhalers,
    kidney=kidney,
    leuk=leuk,
    leukfr=leukfr,
    lsat=lsat,
    magnesium=magnesium,
    mice=mice,
    oxford=oxford,
    pumps=pumps,
    rats=rats,
    salm=salm,
    seeds=seeds,
    stacks=stacks,
    surgical_simple=surgical_simple,
    surgical_realistic=surgical_realistic,
)

const VOLUME_2 = (birats=birats, eyes=eyes)

function has_ground_truth(m::Symbol)
    if m in union(keys(VOLUME_1), keys(VOLUME_2))
        return haskey(getfield(BUGSExamples, m), :reference_results)
    else
        return false
    end
end

# row-major reshape, not robust, use with caution
function rreshape(v::Vector, dim)
    return permutedims(reshape(v, reverse(dim)), length(dim):-1:1)
end   

end