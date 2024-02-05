# The Refactored Compiler

## `evaluate`s

- `simplify_lhs` (which calls `simplify_lhs_eval` on the indices)
  - LHS can only be `Symbol` or a `Expr(:ref, ...)`
  - In the latter case, the indices can be arithmetic expressions
    - Only allow functions: `+, -, *` (currently also allow `/` but maybe shouldn't as it produces `Float64`)
    - Can contain array indexing to data arrays and use these values in the arithmetic expressions
  - `simplify_lhs_eval` is a simple and restrictive evaluation function
    - Its performance still rather slow compare to compiled code, but at least in the first pass, we can trade performance with customized behaviors
  - We want to check the indices to decide the size of the arrays, so we need to evaluate the indices
    - **The expressions must evaluate to either `Int` or `UnitRange`.**

## taxonomy of BUGS programs according to easiness of dealing with

- all variables are scalars

- all array variables appear once and dependency is super clear
  - all indices are simple linear transformations of the loop variable
  - if two or more loop variables are involved, they do not appear in the same expression (for indexing)
  - no data in indices

  ```julia
  @bugs begin
      for i in 1:10
          x[i] ~ Normal(y[i], 1)
      end
  end
  ```
  
  - programs translated from a plate notation where all variables only appear once is in this case
