using AbstractPPL
using Bijectors
using Documenter
using DynamicPPL
using JuliaBUGS
using Setfield
using Test
using UnPack

using DynamicPPL: getlogp, settrans!!

using JuliaBUGS:
    CollectVariables, program!, Var, Stochastic, Logical, evaluate!!, DefaultContext
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BUGSPrimitives: mean

@testset "Function Unit Tests" begin
    DocMeta.setdocmeta!(
        JuliaBUGS,
        :DocTestSetup,
        :(using JuliaBUGS:
            Var,
            create_array_var,
            replace_constants_in_expr,
            evaluate_and_track_dependencies,
            find_variables_on_lhs,
            evaluate,
            merge_collections,
            scalarize,
            concretize_colon_indexing,
            check_unresolved_indices,
            check_out_of_bounds,
            check_implicit_indexing,
            check_partial_missing_values);
        recursive=true,
    )
    Documenter.doctest(JuliaBUGS; manual=false)
end

@testset "Parser" begin
    include("bugsast.jl")
    include("parser.jl")
end

@testset "Compiler Passes" begin
    # TODO: test output of compiler passes, particularly the array size deduction, nested indexing
end

@testset "Compile $m" for m in [
    :blockers,
    :bones,
    :dogs,
    :dyes,
    :epil,
    :equiv,
    :kidney,
    :leuk,
    :leukfr,
    :lsat,
    :magnesium,
    :mice,
    :oxford,
    :pumps,
    :rats,
    :salm,
    :seeds,
    :stacks,
    :surgical_simple,
    :surgical_realistic,
]
    model_def = JuliaBUGS.BUGSExamples.VOLUME_I[m].model_def
    data = JuliaBUGS.BUGSExamples.VOLUME_I[m].data
    inits = JuliaBUGS.BUGSExamples.VOLUME_I[m].inits[1]
    model = compile(model_def, data, inits)
end

include("run_logp_tests.jl")
@testset "Log Density test for $s" for s in [
    # single stochastic variable tests
    :binomial,
    :gamma,

    # BUGS examples
    :blockers,
    :bones,
    :dogs,
    :rats,
]
    include("logp_tests/$s.jl")
end

@testset "Markov Blanket" begin
    include("graphs.jl")
end

# TODO: add test for AuxiliaryNodeInfo

model_def = @bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0E-6)
    alpha1 ~ dnorm(0.0, 1.0E-6)
    alpha2 ~ dnorm(0.0, 1.0E-6)
    alpha12 ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end

data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21,
)

initializations = Dict(:alpha => 1, :beta => 1)

model = compile(model_def, data, initializations)

using GLMakie, GraphMakie
graphplot(model.g, model.parameters)

