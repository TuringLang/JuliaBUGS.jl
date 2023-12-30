# Differences Between BUGS and JuliaBUGS

## Implicit Indexing

In BUGS, `x[, ]` is used for implicit indexing, which selects all elements from both the first and second dimensions.
In JuliaBUGS, users must explicitly use `Colon (:)` like `x[:, :]` when using the `@bugs` macro.
The `@bugs` macro will insert a Colon when given `x[]`, however, the Julia parser will throw an error if given `x[, ]`.
The original BUGS parser will automatically insert a `Colon (:)` when it encounters `x[, ]`.
