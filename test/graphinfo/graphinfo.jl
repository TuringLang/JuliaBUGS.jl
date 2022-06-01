using AbstractPPL
import AbstractPPL.GraphPPL:GraphInfo, Model, get_dag, set_node_value!, 
                            get_node_value, get_sorted_vertices, get_node_eval,
                            get_nodekind, get_node_input, get_model_values, 
                            set_model_values!, rand, rand!, logdensityof
using SparseArrays
using LinearAlgebra
using Distributions
using Random; Random.seed!(1234)

## Example taken from Mamba
line = Dict{Symbol, Any}(
  :x => [1, 2, 3, 4, 5],
  :y => [1, 3, 3, 3, 5]
)

line[:xmat] = [ones(5) line[:x]]

# just making it a NamedTuple so that the values can be tested later. Constructor should be used as Model(;kwargs...).
model = (
    β = (zeros(2), () -> MvNormal(2, sqrt(1000)), :Stochastic),
    xmat = (line[:xmat], () -> line[:xmat], :Logical), 
    s2 = (1.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
    μ = (zeros(5), (xmat, β) -> xmat * β, :Logical), 
    y = (zeros(5), (μ, s2) -> MvNormal(μ, sqrt(s2)), :Stochastic)
)

# better handling of stochastic and logical nodes. 
# Automatically set logistic nodes initial values to their deterministic values.

# construct the model!
m = Model(; zip(keys(model), values(model))...) # uses Model(; kwargs...) constructor

# test the type of the model is correct
@test m isa Model
sorted_vertices = get_sorted_vertices(m)
@test m isa Model{Tuple(sorted_vertices)}
@test m.g isa GraphInfo <: AbstractModelTrace
@test m.g isa GraphInfo{Tuple(sorted_vertices)}

# test the dag is correct
A = sparse([0 0 0 0 0; 0 0 0 0 0; 0 0 0 0 0; 0 1 1 0 0; 1 0 0 1 0])
@test get_dag(m) == A

@test length(m) == 5
@test eltype(m) == valtype(m)


# check the values from the NamedTuple match the values in the fields of GraphInfo
vals, evals, kinds = AbstractPPL.GraphPPL.getvals(NamedTuple{Tuple(sorted_vertices)}(model))
inputs = (s2 = (), xmat = (), β = (), μ = (:xmat, :β), y = (:μ, :s2))

for (i, vn) in enumerate(keys(m))
    @inferred m[vn]
    @inferred get_node_value(m, vn)
    @inferred get_node_eval(m, vn)
    @inferred get_nodekind(m, vn)
    @inferred get_node_input(m, vn)

    @test vn isa VarName
    @test get_node_value(m, vn) == vals[i]
    @test get_node_eval(m, vn) == evals[i]
    @test get_nodekind(m, vn) == kinds[i]
    @test get_node_input(m, vn) == inputs[i]
end

for node in m 
    @test node isa NamedTuple{fieldnames(GraphInfo)[1:4]}
end

# test Model constructor for model with single parent node
single_parent_m = Model(μ = (1.0, () -> 3, :Logical), y = (1.0, (μ) -> Normal(μ, sqrt(1)), :Stochastic))
@test single_parent_m isa Model{(:μ, :y)}
@test single_parent_m.g isa GraphInfo{(:μ, :y)}

# test setindex
@test_throws AssertionError set_node_value!(m, @varname(s2), [0.0])
@test_throws AssertionError set_node_value!(m, @varname(s2), (1.0,))
set_node_value!(m, @varname(s2), 2.0)
@test get_node_value(m, @varname s2) == 2.0

# test ErrorException for parent node not found
@test_throws ErrorException Model( μ = (1.0, (β) -> 3, :Logical), y = (1.0, (μ) -> Normal(μ, sqrt(1)), :Stochastic))

# test AssertionError thrown for kwargs with the wrong order of inputs
@test_throws AssertionError Model( μ = ((β) -> 3, 1.0, :Logical), y = (1.0, (μ) -> Normal(μ, sqrt(1)), :Stochastic))

# testing random + logdensityof
sample = rand(m)

@test keys(sample) == Tuple(get_sorted_vertices(m))

for vn in keys(m)
    mv = get_node_value(m, vn)
    sv = get(sample, vn)
    @test size(mv) == size(sv)
    @test sv isa typeof(mv)
end

model1 = Model(μ = (3.0, () -> 3.0, :Logical),
               y = (0.0, (μ) -> Normal(μ, 1.0), :Stochastic))

priorsamples = rand(model1, 1000)

@test mean([s.μ for s in priorsamples]) == 3
@test mean([s.y for s in priorsamples]) ≈ 3 atol=2

@test logdensityof(model1, (μ = 3.0, y = 3.0)) == logdensityof(Normal(3.0,1.0), 3.0)

model2 = Model(μ = (3.0, () -> 3.0, :Logical),
               y1 = (0.0, (μ) -> Normal(μ, 1.0), :Stochastic),
               y2 = (0.0, (μ) -> Normal(μ, 1.0), :Stochastic),
               y3 = (0.0, (μ) -> Normal(μ, 1.0), :Stochastic))

model3 = Model(μ = (ones(3) * 3, () -> ones(3) * 3, :Logical),
               y = (zeros(3), (μ) -> MvNormal(μ, I), :Stochastic))

ldmodel1 = logdensityof(model1, (μ = 3.0, y = 3.0))
ldmodel2 = logdensityof(model2, (μ = 3.0, y3 = 3.0, y2 = 3.0, y1 = 3.0))
ldmodel3 = logdensityof(model3, (μ = ones(3) * 3, y = ones(3) * 3))

@test 3 * ldmodel1 == ldmodel2 == ldmodel3