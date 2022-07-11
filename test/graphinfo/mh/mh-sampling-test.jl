using AbstractPPL
import AbstractPPL.GraphPPL:GraphInfo, Model, get_dag, set_node_value!, 
                            get_node_value, get_sorted_vertices, get_node_eval,
                            get_nodekind, get_node_input, get_model_values, 
                            set_model_values!, rand, rand!, logdensityof, 
                            get_model_ref_values, get_nodekind, get_nodes
using Distributions
using LinearAlgebra
using Random
using Test

include("mh-test.jl")

f(a, x, b) = ( a .* x ) .+ b
a = 2.0
b = 5.0
x = collect(0.0:0.1:10.0)
data = f(a, x, b)

m = Model(
    a = (0., () -> truncated(Normal(0.0, 1.0), 0.0, 3.0), :Stochastic), 
    x = (collect(0.0:0.1:10.0), () -> collect(0.0:0.1:10.0), :Logical),
    b = (0., () -> Normal(5.0, 3.0), :Stochastic),
    y = (data, (a, x, b) -> MvNormal(f(a, x, b), 1.0), :Observations)
)

spl = RWMH(MvNormal(zeros(2), I));
samples = sample(m, spl, 2_000);
summarize(samples)

mean_pst = mean(samples)
@test isapprox(mean_pst[:b,:mean], 5.0; atol = 1e-1)
@test isapprox(mean_pst[:a,:mean], 2.0; atol = 1e-1)