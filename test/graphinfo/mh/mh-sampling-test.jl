using AbstractPPL
import AbstractPPL.GraphPPL:GraphInfo, Model, get_dag, set_node_value!, 
                            get_node_value, get_sorted_vertices, get_node_eval,
                            get_nodekind, get_node_input, get_model_values, 
                            set_model_values!, rand, rand!, logdensityof, 
                            get_model_ref_values, get_nodekind
using Distributions
using LinearAlgebra
using Random
using Plots, StatsPlots
include("mh-test.jl")

f(a, x, b) = ( a .* x ) .+ b

data = f(2.0, collect(0.0:0.1:10.0), 5.0) .+ randn(101)

m = Model(
    a = (0., () -> truncated(Normal(0.0, 1.0), 0.0, 3.0), :Stochastic), 
    x = (collect(0.0:0.1:10.0), () -> collect(0.0:0.1:10.0), :Logical),
    b = (0., () -> Normal(5.0, 3.0), :Stochastic),
    y = (data, (a, x, b) -> MvNormal(f(a, x, b), 1.0), :Observations)
)

# add a separate nodekind for Observations that are nsot updated
# during random sampling

spl = RWMH(MvNormal(zeros(2), I))
samples = sample(m, spl, 10_000)

plot(samples)