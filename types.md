# Introduction

BUGS programs, in contrast to some other PPLs, have the sole purpose of implicitly describing a
directed graphical model.  This means that there are not declarations of variables, input, outputs,
etc., nor is order relevant for semantics.  A program like

```
model
{
  for( i in 1 : N ) {
    for( j in 1 : T ) {
      Y[i , j] ~ dnorm(mu[i , j], tau.c)
      mu[i , j] <- alpha[i] + beta[i] * (x[j] - xbar)
    }
    alpha[i] ~ dnorm(alpha.c, alpha.tau)
    beta[i] ~ dnorm(beta.c, beta.tau)
  }
  tau.c ~ dgamma(0.001, 0.001)
  sigma <- 1 / sqrt(tau.c)
  alpha.c ~ dnorm(0.0, 1.0E-6)
  alpha.tau ~ dgamma(0.001, 0.001)
  beta.c ~ dnorm(0.0, 1.0E-6)
  beta.tau ~ dgamma(0.001, 0.001)
  alpha0 <- alpha.c - xbar * beta.c
}
```

denotes only a certain relationship between logical (i.e., deterministic) and stochastic nodes.
Variable are either names of nodes (when on the LHS of a sampling or assignement statement, like
`alpha` or `sigma`), or otherwise constant parts of the “data” (like `N` and `xbar`), with which a
model must be combined to instantiate it.

Loops are just a form of “plate notation”: they allow to concisely express repetition of equal
statements over many constant indices, and are thus equivalent to their rolled-out form given the
data.

> In the BUGS language the type information is fine grained: each component of a tensor can have
> different type information. […] One common case is where some components of a tensor have
> been observed while other components need to be estimated.

# Formalization

The type system of BUGS has several interesting properties compared to an off-the-shelf lambda
calculus language:

1. There are no means to introduce any values except by logical or
   stochastic relations, especially no functions.  All values of function types have to be known
   beforehand.
2. There are no type ascriptions (or “variable declarations”).  The types of involved variables
   are reconstructed solely from their usages in expressions.  (BUGS programs are not ordered; 
   you have to unify constraints over the complete program).
3. There is a simple, non-extensible subtying hierarchy within the primitive types (basically `Int
   <: Float`).
4. Types can be considered “colored” as either logical (`T @ log`) or stochastic (`T @ stoch`).
   These color annotations are propagated through expressions and used to constrain certain
   operations.  They work independently from the subtyping system.
   
The following implementation is heavily influenced by (and uses the same syntax as) the 
algorithmic subtyping and constraint-based type reconstruction chapters from “Types 
and Programming Languages”.

- Typings use `::` instead of `:`, since the latter is the syntax for ranges.
- Type judgements have the most general form `Γ ⊢ e :: T @ α | 𝒞`, where `Γ` is the environment,
  `e` the typed expression, `T` the type, `α` the color, and `𝒞` the set of constraints.  If
  unnecessary, the color and constraint part are left out for readability (resulting in an
  implicit “any color” annotation or the empty constraint set, repectively).
  
TODO: describe coercion semantics when a subtyping rule is applied.

### Types

There are two primitive number types `ℤ` and `ℝ` for whole and real numbers.  Values of these types
cannot be constructed, however; all instances are tensors.  Scalars are just tensors of rank zero,
which are tagged by the primitive types.  `Int` and `Real` serve as abbreviations for these cases.

The other primitives are ranges (which can only consist
of integers), `Void` for statements, logical and stochastic function types (the latter
are used to type distributions), and bijections (basically logical functions with a known 
inverse).

```
T = ℤ | ℝ | Range | Tensor{T, k} | Void | T → T | T ⤳ T | T ↔ T
Int := Tensor{ℤ, 0}
Real := Tensor{ℝ, 0}
```

### Colors

Types can be colored, of the form `T @ α`, where α is `stoch`, `log`, or `∅`.  We have an order
`log ⊏ stoch ⊏ ∅`, implying a meet operation ⊔ such that `stoch ⊔ log = stoch`.  This is used for 
propagating colors through expression: as soon as one part is stochastic, everything derived
from it is tainted, too.

Notably, colors are independent of the rest of the type system; especially, subtyping holds 
independently of colors:

```
    T₁ <: T₂
----------------
T₁ @ α <: T₂ @ β
```

`∅` is only ever used as a placeholder for operations that do not need to check colors, and is 
always left out for readability.

### Subtyping

Nothing interesting to see here: integers are subsumed by reals, and tensors are covariant.

```
------
T <: T
```

```
------
ℤ <: ℝ
```

```
           T₁ <: T₂
------------------------------
Tensor{T₁, k} <: Tensor{T₂, k}
```

(Functions are hence technically invariant, but that is irrelevant as there are no higher-order
function.  TODO: maybe there can be higher-order functions in the stdlib?)

### Variables

Known variables can by typed as-is:

```
x :: T @ α ∈ Γ | 𝒞
------------------
Γ ⊢ x :: T @ α | 𝒞
```

Unknown variables add a typing constraint:

```
          x :: T @ α ∉ Γ | 𝒞
----------------------------------------
Γ ⊢ x :: T @ α | 𝒞 ∪ {typeof(x) = T @ α}
```

TODO: does this make sense? How does it interfere with subtype checks later?

### Application

Regular function application behaves as expected.  The result is the least upper bound of
input colors (i.e., stochastic as soon as one of the arguments is stochastic).  Subtyping
is applied.

```
Γ ⊢ f :: T₁, …, Tₙ → U   Γ ⊢ x₁ :: V₁ @ α₁, …, xₙ :: Vₙ @ αₙ   V₁ <: T₁, …, Vₙ <: Tₙ
------------------------------------------------------------------------------------
                       Γ ⊢ f(x₁, …, xₙ) :: U @ (α₁ ⊔ … ⊔ αₙ)
```

Distribution types behave the same, but always return stochastic values:

```
Γ ⊢ f :: T₁, …, Tₙ ⤳ U   Γ ⊢ x₁ :: V₁ @ α₁, …, xₙ :: Vₙ @ αₙ   V₁ <: T₁, …, Vₙ <: Tₙ
------------------------------------------------------------------------------------
                       Γ ⊢ f(x₁, …, xₙ) :: U @ stoch
```

Indexing is a built-in heavily overloaded operator, so receives its own rule.  The result, as 
for logical function application, is determined by the colors of the input arguments.  The key
difference is that the rank of the resulting tensor is determined by the number of slices, i.e.,
indices which are ranges:

```
               Γ ⊢ x :: Tensor{T, m} @ α
   {i₁, …, iₙ} = {scalar₁, …, scalarₖ} ⊎ {range₁, …, rangeₗ}
       Γ ⊢ scalar₁ :: Int @ β₁, …, scalarₖ :: Int @ βₖ
       Γ ⊢ range₁ :: Range @ γ₁, …, rangeₗ :: Range @ γₗ
----------------------------------------------------------------
Γ ⊢ x[i₁, …, iₙ] :: Tensor{T, l} @ α ⊔ β₁ ⊔ … ⊔ βₖ ⊔ γ₁ ⊔ … ⊔ γₗ
```

Which in simpler terms means: check that all indices are `Int` or `Range`, let `l` be the number
of occurences of `Range`, and infer a type of that rank.  The result has, again, the l.u.b. of 
input colors as its color.

### Simple statements

Both logical and stochastic assignment behave the same and require a logical variable
at their left hand side, and a matching type at the right hand side.  The result types
are hard-coded, though, based on the nature of the assignment.

```
    Γ ⊢ x[…] :: T @ log | 𝒞₁   Γ ⊢ rhs :: T @ stoch | 𝒞₂
------------------------------------------------------------
Γ ⊢ x[…] ~ rhs :: Void | 𝒞₁ ∪ 𝒞₂ ∪ {typeof(x[…]) = T @ stoch}
```

```
     Γ ⊢ x[…] :: T @ log | 𝒞₁   Γ ⊢ rhs :: T @ log | 𝒞₂
--------------------------------------------------------------
Γ ⊢ x[…] <- rhs :: Void | 𝒞₁ ∪ 𝒞₂ ∪ {typeof(x[…]) = T @ log}
```

TODO: should there be a subtyping check?

### Compound statements

We first introduce an artificial sequencing operation, simply merging constraint sets
of successive statements:

```
Γ ⊢ s₁ :: Void | 𝒞₁   Γ ⊢ s₂ :: Void | 𝒞₂
-----------------------------------------
     Γ ⊢ s₁ ; s₂ :: Void | 𝒞₁ ∪ 𝒞₂
```

Given that, for loops can be type checked similarly to lambda abstractions (assuming the
loop variable when checking the body).

```
Γ ⊢ r :: Range @ log | 𝒞₁   Γ, i :: Int @ log ⊢ body :: Void | 𝒞₂
-----------------------------------------------------------------
           Γ ⊢ for (i in r) { body } :: Void | 𝒞₁ ∪ 𝒞₂
```


