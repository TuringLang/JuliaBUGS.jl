# Compile tests

Level Of Testing: a higher level is inclusive of lower levels
* 1: Successfully Compile to `tograph`
* 2: Successfully Compile to `GraphInfo`
* 3: Successfully Run Two Steps of `AbstractMCMC.step` defined in `gibbs.jl` 

| Example Name  | Level of Testing | Compile Time in Minutes (Intel 9th-Gen mobile-h cpu) | Comments |
| ------------- | ---------------- | ---------------------------------------------------- | -------- |
| blocker | 3 | | |
| bones | 2 | 50 | ERROR: MethodError: no method matching cdf(::Distributions.Categorical{Float64, Vector{Float64}}, ::Missing) |
| dogs | 2 | 13 | error due to truncated flat is not defined |
| dyes  | 3 | | |
| epil | 2 | 3 | sampling step encounter error, seems \mu is inf |
| equiv | 3 | | | 
| inhalers | 1 | | a[1], a[2], a[3] forms loops; MethodError(SymbolicPPL.truncated, (Turing.Flat(), -1000, a[2]), 0x00000000000084e2)| 
| kidney | 2 | | compile(model_def, data) | 
| leuk | 2 | | | 
| leukfr | 2 | | | 
| last | 1 | | | 
| magnesium | 3 | | | 
| mice | 2 | | ERROR: MethodError: no method matching cdf(::Distributions.Categorical{Float64, Vector{Float64}}, ::Missing) |
| oxford | 3 | 4 | |
| pumps | 3 | | |
| rats | 3 | | |
| salm | 3 | | |
| seeds | 3 | | |
| stacks | 3 | | |
| surgical_simple | 3 | | |
| surgical_realistic | 3 | | |
