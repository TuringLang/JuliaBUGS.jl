module BUGSExamples

using JuliaBUGS: @bugs

include("Volume_I/Blocker.jl")
include("Volume_I/Bones.jl")
include("Volume_I/Dogs.jl")
include("Volume_I/Dyes.jl")
include("Volume_I/Epil.jl")
include("Volume_I/Equiv.jl")
include("Volume_I/Inhalers.jl")
include("Volume_I/Kidney.jl")
include("Volume_I/Leuk.jl")
include("Volume_I/LeukFr.jl")
include("Volume_I/LSAT.jl")
include("Volume_I/Magnesium.jl")
include("Volume_I/Mice.jl")
include("Volume_I/Oxford.jl")
include("Volume_I/Pumps.jl")
include("Volume_I/Rats.jl")
include("Volume_I/Salm.jl")
include("Volume_I/Seeds.jl")
include("Volume_I/Stacks.jl")
include("Volume_I/Surgical.jl")

include("Volume_II/BiRats.jl")
include("Volume_II/Eyes.jl")

const VOLUME_I = (
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

const VOLUME_II = (birats=birats, eyes=eyes)

function has_ground_truth(m::Symbol)
    if m in union(keys(VOLUME_I), keys(VOLUME_II))
        return haskey(getfield(BUGSExamples, m), :reference_results)
    else
        return false
    end
end

end