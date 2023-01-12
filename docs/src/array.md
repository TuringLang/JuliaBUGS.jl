# Array Interface

There are subtleties involved in using the array syntax of BUGS. 
Two elements of the same array can be one logical variable and one stochastic variable. 

## Size Deduction
The size of data arrays will not be deducted.

Otherwise, the array size will be deduced from the model definition.
The unrolling will evaluate all the indices into concrete values (the exception is stochastic indexing). 
We will treat the largest index as the size of the array for a specific dimension. 

## Nested Indexing
Nested indexing can be the source of many errors, especially while data is involved.

# Colon Indexing 
Users should be cautious when using the colon indexing syntax. 
Colon indexing requires knowledge of the size of the array. 
If a loop bound requires a colon indexing, the potential size information from the loop body will not be concerned. 

# Multivariate Variables