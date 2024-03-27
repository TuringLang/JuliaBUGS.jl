module BUGSExamples

using JuliaBUGS: @bugs

struct Example
    name::String
    model_def::Expr
    data::NamedTuple
    inits::NamedTuple
    inits_alternative::NamedTuple
    reference_results::Union{NamedTuple, Nothing}
end

function load_examples(volume_num::Int)
    example_set = NamedTuple()
    if volume_num == 1 || volume_num == 0
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
        example_set = merge(example_set,
            (
                blockers = blockers,
                bones = bones,
                dogs = dogs,
                dyes = dyes,
                epil = epil,
                equiv = equiv,
                # inhalers=inhalers, # use Chain graph, not supported
                kidney = kidney,
                leuk = leuk,
                leukfr = leukfr,
                lsat = lsat,
                magnesium = magnesium,
                mice = mice,
                oxford = oxford,
                pumps = pumps,
                rats = rats,
                salm = salm,
                seeds = seeds,
                stacks = stacks,
                surgical_simple = surgical_simple,
                surgical_realistic = surgical_realistic
            ))
    end

    if volume_num == 2 || volume_num == 0
        include("Volume_2/BiRats.jl")
        include("Volume_2/Eyes.jl")
        example_set = merge(example_set, (
            birats = birats,
            eyes = eyes
        ))
    end

    return example_set
end

const VOLUME_1 = load_examples(1)
const VOLUME_2 = load_examples(2)

end
