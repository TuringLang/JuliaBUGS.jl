module BUGSExamples

using JuliaBUGS: @bugsast, @bugsmodel_str

include("Volume_I/Blocker.jl")
include("Volume_I/Bones.jl")
include("Volume_I/Dogs.jl")
include("Volume_I/Dyes.jl")
include("Volume_I/Epil.jl")
include("Volume_I/Equiv.jl")
# include("Volume_I/Inhalers.jl")
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

volume_i_examples = [
    :blockers,
    :bones,
    :dogs,
    :dyes,
    :epil,
    :equiv,
    # :inhalers,
    :kidney,
    :leuk,
    :leukfr,
    :lsat,
    :magnesium,
    :mice,
    :oxford,
    :pumps,
    :rats,
    :salm,
    :seeds,
    :stacks,
    :surgical_simple,
    :surgical_realistic,
]

volume_ii_examples = [
    :birats,
    :eyes,
]

examples = vcat(volume_i_examples, volume_ii_examples)

end
