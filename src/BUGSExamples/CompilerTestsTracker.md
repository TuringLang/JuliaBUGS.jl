# Compile tests

* 1: Successfully Compile to `tograph`
* 2: Successfully Compile to `GraphInfo`
* 3: Successfully Run Several Steps of `Sample`

| Example Name  | Level of Testing |
| ------------- | ----------- |
| blocker | 3 |
| bones  | 2 | 
| dogs | 2 |
| dyes  | 3 |
| epil | 2 |
| equiv | 3 |
| inhalers | 1 |
| kidney | 2 |
| leuk | 2 |
| leukfr | 2 | 
| last  | 1 | 
| magnesium | 3 |
| mice | | 
| oxford | | 
| pumps | 3 | 
| rats | | 
| salm | | 
| seeds | | 
| stacks | | 
| surgical_simple | |
| surgical_realistic | | 

- bones ~50min - ERROR: MethodError: no method matching cdf(::Distributions.Categorical{Float64, Vector{Float64}}, ::Missing)
- dogs ~13min - error due to truncated flat is not defined
- epil ~3min - sampling step encounter error, seems \mu is inf
- equiv ~1min
