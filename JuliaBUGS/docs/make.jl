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
        "Tutorials" => [
            "Getting Started" => "getting_started.md",
            "In Depth: Seeds" => "example.md",
        ],
        "Example Gallery" => [
            "Overview" => "examples/index.md",
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
        "Coming from..." => [
            "WinBUGS, OpenBUGS, JAGS" => "guides/differences.md",
            "Turing.jl" => "migration/from_turing.md",
            "R" => "R_interface.md",
        ],
        "Modeling" => [
            "Two Macros: `@bugs` & `@model`" => "two_macros.md",
            "`@model` Macro" => "model_macro.md",
            "Model as a Distribution" => "model_as_distribution.md",
        ],
        "Inference" => [
            "Automatic Differentiation" => "inference/ad.md",
            "Evaluation Modes" => "inference/evaluation_modes.md",
            "Auto-Marginalization" => "inference/auto_marginalization.md",
            "Generated Quantities" => "inference/generated_quantities.md",
            "Fixing Variables (`fix` / `unfix`)" => "inference/fixing.md",
            "Parallel & Distributed Sampling" => "inference/parallel.md",
        ],
        "Guides" => [
            "Pitfalls" => "guides/pitfalls.md",
            "Implementation Tricks" => "guides/tricks.md",
        ],
        "Plotting" => "graph_plotting.md",
        "API Reference" => [
            "General" => "api/api.md",
            "Functions" => "api/functions.md",
            "Distributions" => "api/distributions.md",
        ],
        "Design & Internals" => [
            "`of` Type System" => "of_design_doc.md",
            "Parser" => "developers/parser.md",
            "Source Code Generation" => "developers/source_gen.md",
            "Notes on BUGS Implementations" => "developers/BUGS_notes.md",
        ],
    ],
)
