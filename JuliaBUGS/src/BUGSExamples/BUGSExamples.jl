module BUGSExamples

using JuliaBUGS: JuliaBUGS, @bugs, BUGSModelDef
using JSON

struct Example{DNT <: NamedTuple, INT <: NamedTuple, INT2 <: NamedTuple, RNT}
    name::String
    model_def::Expr
    original_syntax_program::String
    data::DNT
    inits::INT
    inits_alternative::INT2
    reference_results::RNT
end

function Example(name, model_def::BUGSModelDef, rest...)
    return Example(name, model_def.model_def, rest...)
end

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
# 16_Inhalers: compiles to a cyclic graph ("The input graph contains at least one
# loop") because `group[i]` is a logical node used as an index into `mu[group[i], t]`.
# The arity of its Example call was also wrong; that is fixed, but it stays disabled.
# include("./Volume_1/16_Inhalers.jl")
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
    mice = mice,
    kidney = kidney,
    leuk = leuk,
    leukfr = leukfr
)

include("Volume_2/01_Dugongs.jl")
include("Volume_2/02_Orange_trees.jl")
include("Volume_2/03_Multivariate_Orange_trees.jl")
include("Volume_2/04_Biopsies.jl")
include("Volume_2/05_Eyes.jl")
include("Volume_2/06_Hearts.jl")
include("Volume_2/07_Air.jl")
include("Volume_2/08_Cervix.jl")
include("Volume_2/09_Jaws.jl")
include("Volume_2/10_BiRats.jl")
include("Volume_2/11_Schools.jl")
include("Volume_2/12_Ice.jl")
include("Volume_2/13_Beetles.jl")
include("Volume_2/14_Alligators.jl")
include("Volume_2/15_Endo.jl")
include("Volume_2/16_Stagnant.jl")
include("Volume_2/17_Asia.jl")
# include("Volume_2/18_Pigs.jl")
# include("Volume_2/19_Simulating_data.jl")

vol_2 = (
    dugongs = dugongs,
    orange_trees = orange_trees,
    orange_trees_multivariate = orange_trees_multivariate,
    biopsies = biopsies,
    eyes = eyes,
    hearts = hearts,
    air = air,
    cervix = cervix,
    jaws = jaws,
    birats = birats,
    schools = schools,
    # ice = ice,
    beetles = beetles,
    alligators = alligators,
    endo = endo,
    stagnant = stagnant,
    asia = asia
)

include("Volume_3/02_Eye_Tracking.jl")
include("Volume_3/04_Circle.jl")
include("Volume_3/04_HollowSquare.jl")
include("Volume_3/04_Parallelogram.jl")
include("Volume_3/04_Ring.jl")
include("Volume_3/04_SquareMinusCircle.jl")
include("Volume_3/05_Hepatitis.jl")
include("Volume_3/05_Hepatitis_ME.jl")
include("Volume_3/06_Hips1.jl")
include("Volume_3/07_Hips2.jl")
include("Volume_3/08_Hips3.jl")
include("Volume_3/09_Hips4.jl")
include("Volume_3/11_PigWeights.jl")
include("Volume_3/12_Pines.jl")
# Not included: 01_Camel (partially observed multivariate node), 03_Fire (dloglik),
# 10_Jama and 13_St_Veit (interp.lin). See notes.md.

vol_3 = (
    eye_tracking = eye_tracking,
    circle = circle,
    hollow_square = hollow_square,
    parallelogram = parallelogram,
    ring = ring,
    square_minus_circle = square_minus_circle,
    hepatitis = hepatitis,
    hepatitis_me = hepatitis_me,
    hips1 = hips1,
    hips2 = hips2,
    hips3 = hips3,
    hips4 = hips4,
    pig_weights = pig_weights,
    bayes_factors = bayes_factors
)

const VOLUME_1 = vol_1
const VOLUME_2 = vol_2
const VOLUME_3 = vol_3

"""
    volumes()

The registered example volumes, as a `NamedTuple` of `NamedTuple`s.
"""
volumes() = (volume_1 = VOLUME_1, volume_2 = VOLUME_2, volume_3 = VOLUME_3)

"""
    list([io::IO = stdout])

Print every registered example, grouped by volume.
"""
function list(io::IO = stdout)
    for (vol, examples) in pairs(volumes())
        println(io, replace(titlecase(string(vol)), "_" => " "), " (", length(examples), ")")
        for (key, ex) in pairs(examples)
            println(io, "  ", rpad(key, 26), ex.name)
        end
    end
    return nothing
end

end
