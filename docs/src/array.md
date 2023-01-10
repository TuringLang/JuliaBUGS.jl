# Array Interface

The array syntax in BUGS is powerful, but there are subtleties involved in using it. 
Two elements of the same array can be one logical variable and one stochastic variable. 

With nested indexing, the array syntax can be very powerful and complicated. 
Users should be cautious when using the array syntax. 
Generally, arrays should be used in coherent with for loop. 
And users should refrain from using nested indexing, especially with data values in evaluating indices. 

## Size Deduction
If an array is part of the input data, the size of the array will not be deducted.

Otherwise, the size of the array will need to be deduced from the model definition.
The unrolling will evaluate all the indices into concrete values (the exception is stochastic indexing). 
We will simply treat the largest index as the size of the array for a certain dimension. 

# Colon indexing 
User should be especially careful when using the colon indexing syntax. 
Colon indexing requires the knowledge of the size of the array. 
If a loop bound requires a colon indexing, the potential size information from the loop body will not be concerned. 

# Multivariate variables
