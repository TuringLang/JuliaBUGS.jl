# Volume 3 notes

Status of each source file in this directory. "Registered" means the file is included from
`BUGSExamples.jl` and appears in `BUGSExamples.VOLUME_3`.

| File | Key | Registered | Notes |
|---|---|---|---|
| 01_Camel | | no | Partially observed two-dimensional Gaussian (`Y[5, 1:2]`). Not supported in general; the Gaussian case has an analytic form, so this could be revisited. |
| 02_Eye_Tracking | `eye_tracking` | yes | Dirichlet process prior with a discrete `S`. Compiles; 123 parameters. |
| 03_Fire | | no | Uses `dloglik`, which is not in the `@bugs` function allowlist. |
| 04_Circle, 04_HollowSquare, 04_Parallelogram, 04_Ring, 04_SquareMinusCircle | `circle`, `hollow_square`, `parallelogram`, `ring`, `square_minus_circle` | yes | The Fun Shapes set. Two parameters each, no observed data. |
| 05_Hepatitis | `hepatitis` | yes | 248 parameters. |
| 05_Hepatitis_ME | `hepatitis_me` | yes | The measurement-error variant. Its reference results used to be `05_Hepatitis.jl`'s, because the file passed `reference_results` rather than its own `reference_results_me`; fixed. |
| 06_Hips1 | `hips1` | yes | Closed-form variant, so it compiles to zero free parameters. |
| 07_Hips2 | `hips2` | yes | 720 parameters. |
| 08_Hips3 | `hips3` | yes | 12 parameters. |
| 09_Hips4 | `hips4` | yes | 20 parameters. |
| 10_Jama | | no | Uses `interp.lin`, which is not in the `@bugs` function allowlist. |
| 11_PigWeights | `pig_weights` | yes | 3 parameters. |
| 12_Pines | `bayes_factors` | yes | Carlin and Chib pseudo-priors. 7 parameters. |
| 13_St_Veit | | no | Uses `interp.lin`, as 10_Jama does. |

Earlier revisions of this file recorded self-loops or coarse-graph loops as the blocker for
Hips2 through Hips4 and a discrete-variable problem for Eye Tracking. Those four compile as
written and are registered.
