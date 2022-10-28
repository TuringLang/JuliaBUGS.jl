# Compile tests

Level Of Testing: a higher level is inclusive of lower levels
* 1: Successfully Compile to `BUGSGraph`
* 2: Successfully Run Two Steps of `AbstractMCMC.step` defined in `gibbs.jl` 

| Example Name  | Level of Testing | Compile Time in Minutes (Intel 9th-Gen mobile-h cpu) | Comments |
| ------------- | ---------------- | ---------------------------------------------------- | -------- |
| blocker | 2 | | |
| bones | 2 | | |
| dogs | 2 | | |
| dyes  | 2 | | |
| epil | 2 | | |
| equiv | 2 | | | 
| inhalers | 0 | | model variables a[1], a[2], a[3] forms loops, can't compile to a DAG | 
| kidney | 2 | | | 
| leuk | 2 | | | 
| leukfr | 2 | | | 
| last | 2 | | | 
| magnesium | 2 | | | 
| mice | 2 | | |
| oxford | 2 |  | |
| pumps | 2 | | |
| rats | 2 | | |
| salm | 2 | | |
| seeds | 2 | | |
| stacks | 2 | | |
| surgical_simple | 2 | | |
| surgical_realistic | 2 | | |
