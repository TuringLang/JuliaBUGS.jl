"""
    BUGSExamples

A standalone Julia package containing classical BUGS example models with
multi-language representations: original BUGS syntax, JuliaBUGS `@bugs` macro,
JuliaBUGS `@model` macro, Stan, and NumPyro.

**No JuliaBUGS dependency required.** All model code is stored as plain strings.
Users pass them directly to JuliaBUGS functions when needed:

```julia
using JuliaBUGS, BUGSExamples

ex = BUGSExamples.rats
model_def = @bugs(ex.original_syntax_program)
model = compile(model_def, ex.data, ex.inits)
```

## Quick Start

```julia
using BUGSExamples

BUGSExamples.list()                        # Browse all examples
ex = BUGSExamples.rats                     # Access an example
println(ex.original_syntax_program)        # Original BUGS model string
println(ex.model_def)                      # @bugs begin...end form
println(ex.data)                           # Data as NamedTuple
```
"""
module BUGSExamples

include("types.jl")
include("data_loader.jl")

export BUGSExample, VOLUME_1, VOLUME_2

# --- Volume 1 Examples ---

include("Volume_1/01_Rats.jl")
include("Volume_1/02_Pumps.jl")
## TODO: Convert remaining Volume 1 examples (03-20)
## include("Volume_1/03_Dogs.jl")
## include("Volume_1/04_Seeds.jl")
## include("Volume_1/05_Surgical.jl")
## include("Volume_1/06_Magnesium.jl")
## include("Volume_1/07_Salm.jl")
## include("Volume_1/08_Equiv.jl")
## include("Volume_1/09_Dyes.jl")
## include("Volume_1/10_Stacks.jl")
## include("Volume_1/11_Epil.jl")
## include("Volume_1/12_Blocker.jl")
## include("Volume_1/13_Oxford.jl")
## include("Volume_1/14_LSAT.jl")
## include("Volume_1/15_Bones.jl")
## include("Volume_1/17_Mice.jl")
## include("Volume_1/18_Kidney.jl")
## include("Volume_1/19_Leuk.jl")
## include("Volume_1/20_LeukFr.jl")

const VOLUME_1 = (
    rats = rats,
    pumps = pumps,
    ## TODO: Add remaining examples here
)

# --- Volume 2 Examples ---

## TODO: Convert Volume 2 examples
## include("Volume_2/01_Dugongs.jl")
## ...

const VOLUME_2 = (;
    ## TODO: Add Volume 2 examples here
)

# --- Utility functions ---

"""
    list()

Print all available BUGS examples grouped by volume.
"""
function list()
    println("BUGSExamples — Available Models\n")
    println("Volume 1 ($(length(VOLUME_1)) examples):")
    for (name, ex) in pairs(VOLUME_1)
        println("  :$name — $(ex.name)")
    end
    if !isempty(VOLUME_2)
        println("\nVolume 2 ($(length(VOLUME_2)) examples):")
        for (name, ex) in pairs(VOLUME_2)
            println("  :$name — $(ex.name)")
        end
    end
end

"""
    examples()

Return a flat NamedTuple of all available examples across all volumes.
"""
function examples()
    return merge(VOLUME_1, VOLUME_2)
end

export list, examples

end # module BUGSExamples
