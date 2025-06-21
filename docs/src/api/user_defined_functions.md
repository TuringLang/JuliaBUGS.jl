# Define and Use Your Own Functions and Distributions

Out of the box, JuliaBUGS only allows functions and distributions defined in `BUGSPrimitives`, `Base`, and `Distributions.jl` to be used in the model.
With the `@bugs_primitive` macro, users can register their own functions and distributions with JuliaBUGS.
It is important to ensure that any functions used are _pure_ mathematical functions.
This implies that such functions should not alter any external state including but not limited to modifying global variables, writing data to files. (Printing might be okay, but do at discretion.)

```julia
julia> JuliaBUGS.@bugs_primitive function f(x)
    return x + 1
end
f (generic function with 1 method)

julia> JuliaBUGS.f(2)
3
```

alternatively, you can use the `@bugs_primitive` macro to register a function that is already defined in the global scope

```julia
julia> f(x) = x + 1
f (generic function with 1 method)

julia> JuliaBUGS.@bugs_primitive(f);

julia> JuliaBUGS.f(1)
2
```

After registering the function or distributions, they can be used just like any other functions or distributions provided by BUGS.
