# Cache
Adding cache for `substitute` is the same as mutate the rule dictionary after every substitute. The concern is, if we what to support multi-threading, mutating rules might be causing sync issues, although it's unlikely to be severe, given that the mutation won't actually affect the result of `substitute`. 

# Initialization with single array indexing
For now, we only support whole array initialization of array and array elements. i.e., initializations like `g[1] = 1` is not allowed, instead, using `g = [1, 2, 3, 4]`.

# A macro allows user to register their own function
In the future, we should implement a macro `@bugsfunction` that allow users to register functions defined by themselves. This macro will need to at least register a symbolic version of the function, so that symbolic execution can be conducted.

# Ambiguity regarding observations
If a variable is stochastic, then even it is observed, we won't consider it to be a parameter. The separation is required from the beginning. This requires non-trivial efforts as it need to handle the case where an stochastic variable is used for array indexing or loop bounds.
The key question is: do we allow observations to be parameters too. 

# TODO
- [] More distribution function and utility functions

