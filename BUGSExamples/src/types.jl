"""
    BUGSExample

A BUGS example with model code in multiple representations.

All model representations are stored as strings, making this package completely
independent of JuliaBUGS. Users can pass the model definitions directly to
JuliaBUGS functions:

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.rats
model_def = @bugs(ex.original_syntax_program)       # Parse BUGS string → Expr
model = compile(model_def, ex.data, ex.inits)        # Compile to BUGSModel
```

# Fields
- `name::String`: Human-readable name of the example
- `original_syntax_program::String`: Model in original BUGS syntax (`model{...}` string)
- `model_def::String`: Model using `@bugs begin...end` Julia expression syntax (as string)
- `model_function::String`: Model using `@model function...end` syntax (as string, empty if not available)
- `stan_code::String`: Stan model code (empty string if unavailable)
- `numpyro_code::String`: NumPyro/Python model code (empty string if unavailable)
- `data::NamedTuple`: Data for the model
- `inits::NamedTuple`: Initial values for model parameters
- `inits_alternative::NamedTuple`: Alternative initial values
- `reference_results`: Reference posterior results (NamedTuple or nothing)
"""
struct BUGSExample{D<:NamedTuple,I<:NamedTuple,I2<:NamedTuple,R}
    name::String
    original_syntax_program::String
    model_def::String
    model_function::String
    stan_code::String
    numpyro_code::String
    data::D
    inits::I
    inits_alternative::I2
    reference_results::R
end

# Convenience constructor — Stan/NumPyro/model_function optional
function BUGSExample(;
    name::String,
    original_syntax_program::String,
    model_def::String,
    model_function::String="",
    stan_code::String="",
    numpyro_code::String="",
    data::NamedTuple,
    inits::NamedTuple,
    inits_alternative::NamedTuple=inits,
    reference_results=nothing,
)
    return BUGSExample(
        name, original_syntax_program, model_def, model_function,
        stan_code, numpyro_code, data, inits, inits_alternative, reference_results,
    )
end
