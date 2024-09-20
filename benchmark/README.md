This folder contains some benchmarking related code and scripts.

The current targets are nimble and stan.

For nimble, we use the R interface. 

For stan, we will use BridgeStan via Julia.

nimble seems to have two modes, uncompiled mode using R, and compiled mode using C++.
But it seems that to compute the gradient, compiled model is required.

the benchmarking uses bugs examples implemented by stan-devs, the models are genearally optimized for Stan. 
The optimizations include vectorization, changing distributions.

Nimble is also not using the most up to date model from MultiBUGS like JuliaBUGS does.

So the results should not be treated as a precise comparison, both comparing JuliaBUGS to the other two, and comparing between Stan and Nimble.
However, the scale of the speed should be indicative.
