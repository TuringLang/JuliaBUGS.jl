## Aspirations

This mini-project aimed to create a more functional compiler that avoids unrolling all loops. This project is unfinished and not well documented. I tried to write down the intuition, implementation ideas, and reasons for not continuing in this documentation. 

## A Rule-Based Pattern Matching and Term-Rewriting Perspective

For a scalar variable, logical assignment defines a simple rewriting rule. In the case of array indexing, multiple possible rewriting rules can be defined for certain subsets of possible indices. For example, 

```julia
# Loop one
for i in 1:N
	for j in 1:i
		g[i, j] = some_expr # def1
	end
	for j in i+1:N
		g[i, j] = some_expr2 # def2
	end
end
```

The possible indices of `g` form a rectangular region `[1:N, 1:N]`; all tuples of `(i, j)` above the line `i=j` follow `def2`; otherwise, it follows `def1`. 

Then if we want to `eval`uate `g[2, 3]` , because `2 < 3` we know we should use `def2` . 

Although the implementation is not necessarily easy, if indices are affine transformations of loop variables, the intuitions should follow. Complications arise when there are functions of loop variables exist (note, array indexing can also be seen as a function call). The analysis can be largely simplified if the data are available, but this is against our initial goal of abstract analysis without data.

## Variable Scope

(This is a personal view, not representing BUGS’ original design.)

Every variable in a BUGS program is a node in the graph, and assignments define the connection between these nodes. In other words, variables precede pretty much everything else. 

The best analogy of BUGS variables in sequential computer programs is immutable, global variables. The difference is that all BUGS variables should not be ordered by order of variable declaration. 

## The Confusion Regarding Types

Because BUGS programs first go through a partial evaluation phase. Data array elements can be seen as constants. However, before partial evaluation, because we can’t make assumptions about whether an array element is constant, we can only make weak assumptions. Interestingly the program has a different semantic under the weak assumption compared to the program after partial evaluation. This is another reason why program analysis before partial evaluation is challenging.