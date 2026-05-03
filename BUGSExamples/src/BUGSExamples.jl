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

export BUGSExample

# --- Examples ---

include("rats/model.jl")
include("pumps/model.jl")
## TODO: Convert remaining examples
## include("dogs/model.jl")
## include("seeds/model.jl")
## ...

const VOLUME_1 = (
    rats = rats,
    pumps = pumps,
    ## TODO: Add remaining examples here
)

const VOLUME_2 = (;
    ## TODO: Add Volume 2 examples here
)

export VOLUME_1, VOLUME_2

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
