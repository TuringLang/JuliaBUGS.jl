# Integrating R in Julia

Julia offers a seamless interface to the [`R` language](https://www.r-project.org/about.html). 

- The [`RCall.jl`](https://github.com/JuliaInterop/RCall.jl) package enables interaction with R functions in Julia.
- The [`RData.jl`](https://github.com/JuliaData/RData.jl) package allows interfacing with R data in Julia.

## Reading BUGS `data` and `init` from R like lists
> **Warning**: The data layout in BUGS assumes that the data is stored in row-major order, while R uses column-major order. This discrepancy can lead to issues. [`Stan`](https://mc-stan.org/) developers have transformed the data and initializations of example BUGS models for R, which can be found [here](https://github.com/stan-dev/example-models/tree/master/bugs_examples).

### Reading the `list` data structure from R
The data for `Rats` is available [here](https://chjackson.github.io/openbugsdoc/Examples/Ratsdata.html). 

In Julia, we can read this data into a Julia dictionary using the `RCall.jl` package.
```julia-repl
julia> using RCall

julia> data = R"
list(
    x = c(8.0, 15.0, 22.0, 29.0, 36.0), xbar = 22, N = 30, T = 5,
    Y = structure(
        .Data = c(
            151, 199, 246, 283, 320,
            145, 199, 249, 293, 354,
            147, 214, 263, 312, 328,
            155, 200, 237, 272, 297,
            135, 188, 230, 280, 323,
            159, 210, 252, 298, 331,
            141, 189, 231, 275, 305,
            159, 201, 248, 297, 338,
            177, 236, 285, 350, 376,
            134, 182, 220, 260, 296,
            160, 208, 261, 313, 352,
            143, 188, 220, 273, 314,
            154, 200, 244, 289, 325,
            171, 221, 270, 326, 358,
            163, 216, 242, 281, 312,
            160, 207, 248, 288, 324,
            142, 187, 234, 280, 316,
            156, 203, 243, 283, 317,
            157, 212, 259, 307, 336,
            152, 203, 246, 286, 321,
            154, 205, 253, 298, 334,
            139, 190, 225, 267, 302,
            146, 191, 229, 272, 302,
            157, 211, 250, 285, 323,
            132, 185, 237, 286, 331,
            160, 207, 257, 303, 345,
            169, 216, 261, 295, 333,
            157, 205, 248, 289, 316,
            137, 180, 219, 258, 291,
            153, 200, 244, 286, 324
        ),
        .Dim = c(30, 5)
    )
)
"
RObject{VecSxp}
$x
[1]  8 15 22 29 36

$xbar
[1] 22

$N
[1] 30

$T
[1] 5

$Y
      [,1] [,2] [,3] [,4] [,5]
 [1,]  151  141  154  157  132
 [2,]  199  189  200  212  185
 [3,]  246  231  244  259  237
 [4,]  283  275  289  307  286
 [5,]  320  305  325  336  331
 [6,]  145  159  171  152  160
 [7,]  199  201  221  203  207
 [8,]  249  248  270  246  257
 [9,]  293  297  326  286  303
[10,]  354  338  358  321  345
[11,]  147  177  163  154  169
[12,]  214  236  216  205  216
[13,]  263  285  242  253  261
[14,]  312  350  281  298  295
[15,]  328  376  312  334  333
[16,]  155  134  160  139  157
[17,]  200  182  207  190  205
[18,]  237  220  248  225  248
[19,]  272  260  288  267  289
[20,]  297  296  324  302  316
[21,]  135  160  142  146  137
[22,]  188  208  187  191  180
[23,]  230  261  234  229  219
[24,]  280  313  280  272  258
[25,]  323  352  316  302  291
[26,]  159  143  156  157  153
[27,]  210  188  203  211  200
[28,]  252  220  243  250  244
[29,]  298  273  283  285  286
[30,]  331  314  317  323  324
```

alternatively, `reval(s::String)` will produce the same result in this case.

If the data is stores in a file, user can use function (may require customizing the function to fit specific needs)
```julia
function read_rlist_to_dictionary(filepath::String)
    r_data = open(filepath) do f
        s = read(f, String)
        reval(s)
    end
    return rcopy(r_data)
end
```
, and save the result to a Julia variable and access the data as a Julia dictionary
```julia-repl
julia> rcopy(data)
OrderedDict{Symbol, Any} with 5 entries:
  :x    => [8.0, 15.0, 22.0, 29.0, 36.0]
  :xbar => 22.0
  :N    => 30.0
  :T    => 5.0
  :Y    => [151.0 141.0 … 157.0 132.0; 199.0 189.0 … 212.0 185.0; … ; 298.0 273.0 … 285.0 286.0; 331.0 314.0 … 323.0 324.0]
```

It is worth noting that `rcopy` will automatically convert data names contains `.` to `_` in Julia. E.g.
```julia
julia> rcopy(R"list(a.b = 1)")
OrderedDict{Symbol, Any} with 1 entry:
  :a_b => 1.0
```

### Transform Data read from R to Julia convention
If you want to load data using the R interface, but the data source is in the same layout as BUGS, you can process the data in Julia, for instance
```julia-repl
# define a row-major reshape function, because Julia's `reshape` is column-major
julia> function rreshape(v::Vector, dim)
           return permutedims(reshape(v, reverse(dim)), length(dim):-1:1)
       end   
rreshape (generic function with 1 method)

julia> rreshape(vcat(data[:Y]...), (30, 5))
30×5 Matrix{Float64}:
 151.0  199.0  246.0  283.0  320.0
 145.0  199.0  249.0  293.0  354.0
 147.0  214.0  263.0  312.0  328.0
 155.0  200.0  237.0  272.0  297.0
 135.0  188.0  230.0  280.0  323.0
 159.0  210.0  252.0  298.0  331.0
 141.0  189.0  231.0  275.0  305.0
 159.0  201.0  248.0  297.0  338.0
   ⋮                         
 146.0  191.0  229.0  272.0  302.0
 157.0  211.0  250.0  285.0  323.0
 132.0  185.0  237.0  286.0  331.0
 160.0  207.0  257.0  303.0  345.0
 169.0  216.0  261.0  295.0  333.0
 157.0  205.0  248.0  289.0  316.0
 137.0  180.0  219.0  258.0  291.0
 153.0  200.0  244.0  286.0  324.0
```

Please always verify the data before using.