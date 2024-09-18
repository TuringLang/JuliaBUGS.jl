This folder contains some benchmarking related code and scripts.

The current targets are nimble and stan.

For nimble, we use the R interface. 

For stan, we will use BridgeStan via Julia.

nimble seems to have two modes, uncompiled mode using R, and compiled mode using C++.

Stan doesn't handle discrete parameters, given the time, the first order thing to try here is to just benchmark the models without discrete parameters. 
The reason stan developers have already translated some models into stan, and I don't want to make unnecessary effort now rewriting the example programs. 
