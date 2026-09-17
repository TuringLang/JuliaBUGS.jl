using Documenter
using DocumenterMermaid
using JuliaBUGS
using AbstractPPL
using MetaGraphsNext
using JuliaBUGS.BUGSPrimitives

makedocs(;
    sitename="JuliaBUGS.jl",
    warnonly=[:cross_references, :doctest],
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
        hide(
            "Examples" => "examples/index.md",
            [
                "Rats" => "examples/volume_1/rats.md",
                "Pumps" => "examples/volume_1/pumps.md",
                "Dogs" => "examples/volume_1/dogs.md",
                "Seeds" => "examples/volume_1/seeds.md",
                "Surgical" => "examples/volume_1/surgical.md",
                "Magnesium" => "examples/volume_1/magnesium.md",
                "Salm" => "examples/volume_1/salm.md",
                "Equiv" => "examples/volume_1/equiv.md",
                "Dyes" => "examples/volume_1/dyes.md",
                "Stacks" => "examples/volume_1/stacks.md",
                "Epil" => "examples/volume_1/epil.md",
                "Blockers" => "examples/volume_1/blockers.md",
                "Oxford" => "examples/volume_1/oxford.md",
                "LSAT" => "examples/volume_1/lsat.md",
                "Bones" => "examples/volume_1/bones.md",
                "Mice" => "examples/volume_1/mice.md",
                "Kidney" => "examples/volume_1/kidney.md",
                "Leuk" => "examples/volume_1/leuk.md",
                "LeukFr" => "examples/volume_1/leukfr.md",
            ],
        ),
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
