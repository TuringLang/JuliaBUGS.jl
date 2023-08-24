# BUGS Parser

The macro [`@bugs`](@ref) produces a Julia `Expr` object that represents the BUGS model definition.

If the input is a `String`, it's assumed to be a program in the original BUGS language. In this case, the macro will first convert the program to an equivalent Julia program, then use the Julia parser to parse the program into an `Expr` object.

Both model definitions written in Julia and those written in the original BUGS and subsequently parsed are now represented as a Julia `Expr` object. These objects go through syntax checking and post-processing to create the input for the `compile` function.

Below, we describe how the original BUGS program is translated to an equivalent Julia program and detail the post-processing done to the `Expr` object.

## BUGS to Julia Translation

In this section, we refer to the translation program as the "parser" and the translating process as "parsing". Although the parser doesn't produce a syntax tree, it does follow the form of a recursive descent parser, building a Julia program in the form of a vector of tokens rather than a syntax tree.

This general implementation is heavily inspired by [`JuliaSyntax.jl`](https://github.com/JuliaLang/JuliaSyntax.jl), the official parser for Julia since version 1.10.

The BUGS parser implemented here takes a token stream with a recursive descent structure and checks the program's correctness. Here's how it works:

1. Use [`tokenize`](https://julialang.github.io/JuliaSyntax.jl/dev/api/#JuliaSyntax.tokenize) to obtain the token vector.
2. Inspect the tokens and build the Julia version of the program as a vector of tokens.
3. Push the token to the Julia version of the program vector when appropriate.
4. Detect errors and make necessary alterations to tokens, such as deletion, combination, or replacement.

During the recursive descent, BUGS syntax tokens will be translated into Julia syntax tokens. Some tokens will remain as they are, while others will be transformed, removed, or new tokens may be added.

The parser will throw an error if it encounters a program that does not adhere to strict BUGS syntax.

### Some Notes on Error Recovery

The current error recovery is ad hoc and primarily rudimentary. If the program is correct, it will produce the correct result. If the program is syntactically or semantically incorrect, the token stream will not be pushed forward, resulting in failure.

The failure detection mechanism checks if two errors occur with the same "current token". If they do, the parser stops and reports the error. This ensures that the parser won't incorrectly parse a flawed program.

## Syntax Checking and Post-Processing

### Transformations on Julia ASTs

These transformations maintain core forms that translate from BUGS to Julia, aiming to produce code as close to executable as possible. Special forms are simplified for pattern matching.

- **Transformation of Tilde Statements**: Tilde (`~`) statements are uniquely parsed in Julia.
    - Example: `dc[i] ~ dunif(0, 20)` becomes `(:~, (:ref, :dc, :i), (:call, :dunif, 0, 20))`.
- **Handling of Logical Assignments with Link Functions**: The automatically created block on the right-hand side is removed in logical assignments.
    - Example: `logit(p) <- x` becomes `(:(=), (:call, :logit, :x), :y)`.
- **Conversion of Censoring and Truncation Annotations**: These annotations are converted into `:censored` and `:truncated` forms.
    - Example: `dnorm(x, μ) C (, 10)` becomes `(:censored, (:call, :dnorm, :x, :μ), :nothing, 100)`.
- **Automatic Filling of Empty Ranges**: Empty ranges are filled with slices.
    - Example: `x[,]` becomes `(:ref, :x, :(:), :(:))`.
- **Normalization of Forms with Lowered Representation**: Forms with both a `:call` representation and their own lowered form are normalized to the latter.
    - Currently, this includes `getindex` to `:ref`, and `:` to `:(:)`.
- **Complete Removal of `LineNumberNode`s**.
- **Preservation of Interpolations and Quasi-Quotations**.

### Post-Processing of Julia ASTs

- **Replacement of `step` function with `_step`**: As `step` has a different meaning in BUGS.
- **Replacement of Link Function Calls on the LHS with the Corresponding Inverse Link Function on the RHS**.
    - Example: `(:(=), (:call, :logit, :x), :y)` becomes `(:(=), :x, (:call, :logistic, :y))`.
- **Transformation of `cumulative`, `density`, and `deviance` functions**: These functions are transformed into corresponding function calls that align with the context of the distribution they evaluate.
