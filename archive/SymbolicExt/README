The code in this folder is an early version of the JuliaBUGS compiler, which employs `Symbolics.jl` for analysis and code generation. It was succeeded by the current version due to scalability constraints.

Despite these constraints, this version provides enhanced support for BUGS syntax and semantics, including:
- Permitting function calls within indexing,
- Greater flexibility with logical variables, allowing them to be defined outside a for loop, usable within loop bounds, and at any same or lower scope level.

This functionality is achieved by unrolling all for loops and forming an equation system from the logical assignments. Expressions can then be evaluated using this system with `Symbolics.jl`.

Plans to revisit and optimize this version of the compiler exist for the future.
