# Syntax restrictions

What are not allowed

## LHS

### Checked at parsing ("check model")

* Floating point number is disallowed, e.g. `x[1.0] ~ ...`
  * if the expression contain floating point data variable that is in fact integer, then it is okay, e.g. `x[a[1]] ~ ...` where `a[1] = 1.0`
* BUGS doesn't have `^` for power

### Checked at compile ("compile")

* function application other than `+, -, *, /`
* indices that are not integer
