module BUGSExamples

using JuliaBUGS: @bugs
using JSON

struct Example
    name::String
    model_def::Expr
    original_syntax_program::String
    data::NamedTuple
    inits::NamedTuple
    inits_alternative::NamedTuple
    reference_results::Union{NamedTuple, Nothing}
end

function load_example_volume(volume_num::Int)
    if volume_num == 1
        include("./Volume_1/01_Rats.jl")
        include("./Volume_1/02_Pumps.jl")
        include("./Volume_1/03_Dogs.jl")
        include("./Volume_1/04_Seeds.jl")
        include("./Volume_1/05_Surgical.jl")
        include("./Volume_1/06_Magnesium.jl")
        include("./Volume_1/07_Salm.jl")
        include("./Volume_1/08_Equiv.jl")
        include("./Volume_1/09_Dyes.jl")
        include("./Volume_1/10_Stacks.jl")
        include("./Volume_1/11_Epil.jl")
        include("./Volume_1/12_Blocker.jl")
        include("./Volume_1/13_Oxford.jl")
        include("./Volume_1/14_LSAT.jl")
        include("./Volume_1/15_Bones.jl")
        #include("./Volume_1/16_Inhalers.jl")
        include("./Volume_1/17_Mice.jl")
        include("./Volume_1/18_Kidney.jl")
        include("./Volume_1/19_Leuk.jl")
        include("./Volume_1/20_LeukFr.jl")

        vol_1 = (
            rats = rats,
            pumps = pumps,
            dogs = dogs,
            seeds = seeds,
            surgical_simple = surgical_simple,
            surgical_realistic = surgical_realistic,
            magnesium = magnesium,
            salm = salm,
            equiv = equiv,
            dyes = dyes,
            stacks = stacks,
            epil = epil,
            blockers = blockers,
            oxford = oxford,
            lsat = lsat,
            bones = bones,
            #inhalers = inhalers, # chain graph is not supported
            mice = mice,
            kidney = kidney,
            leuk = leuk,
            leukfr = leukfr
        )
        return vol_1
    elseif volume_num == 2
        include("Volume_2/BiRats.jl")
        include("Volume_2/Eyes.jl")
        vol_2 = (
            birats = birats,
            eyes = eyes
        )
        return vol_2
    else
        @warn("Volume number $volume_num not supported yet.")
        return nothing
    end
end

const VOLUME_1 = load_example_volume(1)
const VOLUME_2 = load_example_volume(2)

end
