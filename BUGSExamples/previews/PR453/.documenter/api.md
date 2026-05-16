
# API Reference {#API-Reference}



## Types {#Types}
<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.BUGSExample' href='#BUGSExamples.BUGSExample'><span class="jlbinding">BUGSExamples.BUGSExample</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
BUGSExample
```


A BUGS example with model code in multiple representations.

All model representations are stored as strings, making this package completely independent of JuliaBUGS. Users can pass the model definitions directly to JuliaBUGS functions:

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.rats
model_def = @bugs(ex.original_syntax_program)       # Parse BUGS string → Expr
model = compile(model_def, ex.data, ex.inits)        # Compile to BUGSModel
```


**Fields**
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
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/740fb2179ad431abe2c142a2bea6ee6c7f3f14aa/BUGSExamples/src/types.jl#L1-L28" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Functions {#Functions}
<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.list' href='#BUGSExamples.list'><span class="jlbinding">BUGSExamples.list</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
list()
```


Print all available BUGS examples grouped by volume.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/740fb2179ad431abe2c142a2bea6ee6c7f3f14aa/BUGSExamples/src/BUGSExamples.jl#L61-L65" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.examples' href='#BUGSExamples.examples'><span class="jlbinding">BUGSExamples.examples</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
examples()
```


Return a flat NamedTuple of all available examples across all volumes.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/740fb2179ad431abe2c142a2bea6ee6c7f3f14aa/BUGSExamples/src/BUGSExamples.jl#L80-L84" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Module {#Module}
<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.BUGSExamples' href='#BUGSExamples.BUGSExamples'><span class="jlbinding">BUGSExamples.BUGSExamples</span></a> <Badge type="info" class="jlObjectType jlModule" text="Module" /></summary>



```julia
BUGSExamples
```


A standalone Julia package containing classical BUGS example models with multi-language representations: original BUGS syntax, JuliaBUGS `@bugs` macro, JuliaBUGS `@model` macro, Stan, and NumPyro.

**No JuliaBUGS dependency required.** All model code is stored as plain strings. Users pass them directly to JuliaBUGS functions when needed:

```julia
using JuliaBUGS, BUGSExamples

ex = BUGSExamples.rats
model_def = @bugs(ex.original_syntax_program)
model = compile(model_def, ex.data, ex.inits)
```


**Quick Start**

```julia
using BUGSExamples

BUGSExamples.list()                        # Browse all examples
ex = BUGSExamples.rats                     # Access an example
println(ex.original_syntax_program)        # Original BUGS model string
println(ex.model_def)                      # @bugs begin...end form
println(ex.data)                           # Data as NamedTuple
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/740fb2179ad431abe2c142a2bea6ee6c7f3f14aa/BUGSExamples/src/BUGSExamples.jl#L1-L30" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Internal {#Internal}
<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples._dict_to_namedtuple-Tuple{AbstractDict}' href='#BUGSExamples._dict_to_namedtuple-Tuple{AbstractDict}'><span class="jlbinding">BUGSExamples._dict_to_namedtuple</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_dict_to_namedtuple(d::Dict) -> NamedTuple
```


Convert a Dict{String, Any} to a NamedTuple, converting nested arrays properly. Handles BUGS-style dot-separated names via Julia&#39;s `var"name.subname"` syntax.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/740fb2179ad431abe2c142a2bea6ee6c7f3f14aa/BUGSExamples/src/data_loader.jl#L3-L8" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.load_example_data-Tuple{String}' href='#BUGSExamples.load_example_data-Tuple{String}'><span class="jlbinding">BUGSExamples.load_example_data</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
load_example_data(filepath::String)
```


Load a JSON data file and return structured data for a BUGSExample.

Each JSON file should have keys: `"data"`, `"inits"`, and optionally `"inits_alternative"` and `"reference_results"`.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/740fb2179ad431abe2c142a2bea6ee6c7f3f14aa/BUGSExamples/src/data_loader.jl#L60-L67" target="_blank" rel="noreferrer">source</a></Badge>

</details>

