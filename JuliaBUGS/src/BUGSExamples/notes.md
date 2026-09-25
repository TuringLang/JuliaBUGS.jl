# BUGS Examples

| Volume | Example Name | HMC | Comments |
|--------|--------------|-----|----------|
| 1 | Rats | Yes | |
| 1 | Pumps | Yes | |
| 1 | Dogs | No | |
| 1 | Seeds | Yes | |
| 1 | Surgical(Simple) | Yes | |
| 1 | Surgical(Complex) | Yes | Returns `b` values instead of `p` values |
| 1 | Magnesium | Yes | Minor deviations |
| 1 | Salm | Yes | |
| 1 | Equiv | Yes | |
| 1 | Dyes | No | Low ESS |
| 1 | Stacks | Yes | |
| 1 | Epil | No | |
| 1 | Blocker | Yes | |
| 1 | Oxford | Yes | |
| 1 | LSAT | No | MultiBUGS has additional comments |
| 1 | Bones | No | Issues with categorical distribution |
| 1 | Mice | Partial | `r` correct, others have correct signs but wrong values |
| 1 | Kidney | Yes | |
| 1 | Leuk | Yes | |
| 1 | Leukfr | Yes | |
| 2 | Dugongs | Yes | |
| 2 | Orange | No | |
| 2 | MvOrange | No | Possible numerical issues or funnel effects |
| 2 | Biopsies | Error | Type conversion issue between Int and Float for HMC. Note: until recently this example was also being given another example's initial values, because its own were misspelled `intis`; the HMC status here predates that fix and has not been rechecked. |
| 2 | Eyes | Error | Same issue as Biopsies |
| 2 | Hearts | Error | Same issue as Eyes |
| 2 | Air | Yes | |
| 2 | Cervix | Error | Same issue as Eyes and Hearts |
| 2 | Jaws | Error | Numerical issue with PSD matrix |
| 2 | Birats | No | Sampler does run, but NUTS takes too long to complete |
| 2 | Schools | Unknown | Large example. Runs but not fully tested |
| 2 | Ice | Partial | Issues with beta[1], betamean, etc. |
| 2 | Beetles | Yes | |
| 2 | Alligators | Yes | |
| 2 | Endo | Yes | |
| 2 | Stagnant | N/A | Demonstration of failed convergence |
| 2 | Asia | No | Issues with many categorical variables |
| 2 | Pigs | No | The source file in this repository is empty. |
| 2 | Simulated data | N/A | The source file in this repository is empty. Demonstration, not for inference testing |

Volume 3 is tracked separately in [Volume_3/notes.md](Volume_3/notes.md).
Volume 4 is not registered; only Methadone exists in this repository, and its data file
is too large to load at package load time.
