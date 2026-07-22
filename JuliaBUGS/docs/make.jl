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
        "Get Started" => [
            "Getting Started" => "getting_started.md",
            "In-Depth Tutorial: Seeds" => "example.md",
        ],
        "User Guide" => [
            "Modeling" => [
                "Choosing `@bugs` or `@model`" => "two_macros.md",
                "Defining Models with `@model`" => "model_macro.md",
                "Structuring Parameters with `of`" => "of_design_doc.md",
                "Inspecting Model Graphs" => "graph_plotting.md",
                "Common Modeling Pitfalls" => "guides/pitfalls.md",
                "BUGS Modeling Techniques" => "guides/tricks.md",
            ],
            "Inference" => [
                "Automatic Differentiation" => "inference/ad.md",
                "Evaluation Modes" => "inference/evaluation_modes.md",
                "Discrete Variables and Auto-Marginalization" =>
                    "inference/auto_marginalization.md",
                "Slice Sampling" => "inference/slice_sampling.md",
                "Parallel & Distributed Sampling" => "inference/parallel.md",
            ],
            "Working with Models" => [
                "Generated Quantities" => "inference/generated_quantities.md",
                "Fixing Variables (`fix` / `unfix`)" => "inference/fixing.md",
                "Model as a Distribution" => "model_as_distribution.md",
            ],
        ],
        hide("Examples" => "examples/index.md", [
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
        ]),
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
