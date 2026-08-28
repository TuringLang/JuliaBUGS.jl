using Documenter
using DocumenterMermaid
using JuliaBUGS
using AbstractPPL
using MetaGraphsNext
using JuliaBUGS.BUGSPrimitives

makedocs(;
    sitename="JuliaBUGS.jl",
    warnonly=[:cross_references, :doctest],
    format=Documenter.HTML(;
        assets=["assets/doodleppl.css", "assets/doodleppl.js"], collapselevel=1
    ),
    pages=[
        "Home" => "index.md",
        "Get Started" => "getting_started.md",
        "User Guide" => [
            "Modeling" => [
                "Choosing `@bugs` or `@model`" => "two_macros.md",
                "Defining Models with `@model`" => "model_macro.md",
                "Initial Values" => "guides/initialization.md",
                "Structuring Parameters with `of`" => "of_design_doc.md",
                "Inspecting Model Graphs" => "graph_plotting.md",
                "Common Modeling Pitfalls" => "guides/pitfalls.md",
                "BUGS Modeling Techniques" => "guides/tricks.md",
            ],
            "Inference" => [
                "Automatic Differentiation" => "inference/ad.md",
                "Evaluation Modes" => "inference/evaluation_modes.md",
                "Discrete Variables and Auto-Marginalization" => "inference/auto_marginalization.md",
                "Slice Sampling" => "inference/slice_sampling.md",
                "Sampling Output Formats" => "inference/output_formats.md",
                "Parallel & Distributed Sampling" => "inference/parallel.md",
            ],
            "Working with Models" => [
                "Generated Quantities" => "inference/generated_quantities.md",
                "Fixing Variables (`fix` / `unfix`)" => "inference/fixing.md",
                "Model as a Distribution" => "model_as_distribution.md",
            ],
        ],
        "Examples" => [
            "Overview" => "examples/index.md",
            "Volume 1" => [
                "Rats" => "examples/rats.md",
                "Pumps" => "examples/pumps.md",
                "Dogs" => "examples/dogs.md",
                "Seeds" => "examples/seeds.md",
                "Surgical" => "examples/surgical.md",
                "Magnesium" => "examples/magnesium.md",
                "Salm" => "examples/salm.md",
                "Equiv" => "examples/equiv.md",
                "Dyes" => "examples/dyes.md",
                "Stacks" => "examples/stacks.md",
                "Epil" => "examples/epil.md",
                "Blockers" => "examples/blockers.md",
                "Oxford" => "examples/oxford.md",
                "LSAT" => "examples/lsat.md",
                "Bones" => "examples/bones.md",
                "Mice" => "examples/mice.md",
                "Kidney" => "examples/kidney.md",
                "Leuk" => "examples/leuk.md",
                "LeukFr" => "examples/leukfr.md",
            ],
            "Volume 2" => [
                "Overview" => "examples/volume_2/index.md",
                "Dugongs" => "examples/volume_2/dugongs.md",
                "Orange Trees" => "examples/volume_2/orange_trees.md",
                "Orange Trees (multivariate)" => "examples/volume_2/orange_trees_multivariate.md",
                "Biopsies" => "examples/volume_2/biopsies.md",
                "Eyes" => "examples/volume_2/eyes.md",
                "Hearts" => "examples/volume_2/hearts.md",
                "Air" => "examples/volume_2/air.md",
                "Cervix" => "examples/volume_2/cervix.md",
                "Jaws" => "examples/volume_2/jaws.md",
                "BiRats" => "examples/volume_2/birats.md",
                "Schools" => "examples/volume_2/schools.md",
                "Beetles" => "examples/volume_2/beetles.md",
                "Alligators" => "examples/volume_2/alligators.md",
                "Endo" => "examples/volume_2/endo.md",
                "Stagnant" => "examples/volume_2/stagnant.md",
                "Asia" => "examples/volume_2/asia.md",
            ],
            "Volume 3" => [
                "Overview" => "examples/volume_3/index.md",
                "Eye Tracking" => "examples/volume_3/eye_tracking.md",
                "Circle" => "examples/volume_3/circle.md",
                "Hollow Square" => "examples/volume_3/hollow_square.md",
                "Parallelogram" => "examples/volume_3/parallelogram.md",
                "Ring" => "examples/volume_3/ring.md",
                "Square minus Circle" => "examples/volume_3/square_minus_circle.md",
                "Hepatitis" => "examples/volume_3/hepatitis.md",
                "Hepatitis (measurement error)" => "examples/volume_3/hepatitis_me.md",
                "Hips1" => "examples/volume_3/hips1.md",
                "Hips2" => "examples/volume_3/hips2.md",
                "Hips3" => "examples/volume_3/hips3.md",
                "Hips4" => "examples/volume_3/hips4.md",
                "Pig Weights" => "examples/volume_3/pig_weights.md",
                "Bayes Factors" => "examples/volume_3/bayes_factors.md",
            ],
        ],
        "Migration Guides" => [
            "WinBUGS, OpenBUGS, JAGS" => "guides/differences.md",
            "Turing.jl" => "migration/from_turing.md",
            "R" => "R_interface.md",
        ],
        "Reference" => [
            "Julia API" => "api/api.md",
            "Functions" => "api/functions.md",
            "Distributions" => "api/distributions.md",
        ],
        "Developer Guide" => [
            "Parser" => "developers/parser.md",
            "Source Code Generation" => "developers/source_gen.md",
            "Notes on BUGS Implementations" => "developers/BUGS_notes.md",
        ],
    ],
)
