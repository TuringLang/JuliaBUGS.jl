| Example Name | HMC | Comments |
|--------------|-----|----------|
| Rats | Yes | |
| Pumps | Yes | |
| Dogs | No | |
| Seeds | Yes | |
| Surgical(Simple) | Yes | |
| Surgical(Complex) | Yes | Returns `b` values instead of `p` values |
| Magnesium | Yes | Minor deviations. 4000 samples, 1000 adaptations: ~36s on M2 |
| Salm | Yes | 4000 samples, 1000 adaptations: ~27s on M2. Seems slow |
| Equiv | Yes | |
| Dyes | No | Needs hyperparameter tuning. Low ESS |
| Stacks | Yes | |
| Epil | No | |
| Blocker | Yes | |
| Oxford | Yes | |
| LSAT | No | MultiBUGS has additional comments |
| Bones | No | Issues with categorical distribution |
| Mice | Partial | `r` correct, others have correct signs but wrong values |
| Kidney | Yes | |
| Leuk | Yes | |
| Leukfr | Yes | |
| Dugongs | Yes | |
| Orange | No | |
| MvOrange | No | Possible numerical issues or funnel effects |
| Biopsies | Error | Type conversion issue between Int and Float for HMC. Needs testing with MH. Error creating ADGradient |
| Eyes | Error | Same issue as Biopsies |
| Hearts | Error | Same issue as Eyes |
| Air | Yes | |
| Cervix | Error | Same issue as Eyes and Hearts |
| Jaws | Error | Numerical issue with PSD matrix |
| Birats | Runs | NUTS takes too long to complete |
| Schools | Runs | Large example. Runs but not fully tested |
| Ice | Partial | Issues with beta[1], betamean, etc. |
| Beetles | Yes | |
| Alligators | Yes | |
| Endo | Yes | |
| Stagnant | N/A | Demonstration of failed convergence |
| Asia | No | Issues with many categorical variables |
| Pigs | No | Issues with many categorical variables |
| Simulated data | N/A | Demonstration, not for inference testing |
