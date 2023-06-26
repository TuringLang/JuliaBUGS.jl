using Bijectors
using DynamicPPL
using JuliaBUGS
using Setfield
using Test
using UnPack

using JuliaBUGS: CollectVariables, program!, Var, Stochastic, Logical, evaluate!!, DefaultContext
using JuliaBUGS.BUGSPrimitives
##

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
            merge_dicts,
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
    # TODO: add more explicit tests for the parser
    include("bugsast.jl")
end

@testset "Compiler Passes" begin
    # TODO: ideally, there should be a model that test
    # 1. array size inference, also test bitmaps
    # 2. nested indexing
    # 3. for loops, including nesting
end

@testset "Compile" begin
    # test that all the BUGS examples from volume 1 can be compiled without error
end

@test "Log Joint with DynamicPPL" begin
    @model function rats(Y, x, xbar, N, T)
        var"alpha.c" ~ JuliaBUGS.dnorm(0.0, 1.0E-6)
        var"alpha.tau" ~ JuliaBUGS.dgamma(0.001, 0.001)
        var"beta.c" ~ JuliaBUGS.dnorm(0.0, 1.0E-6)
        var"beta.tau" ~ JuliaBUGS.dgamma(0.001, 0.001)
        var"tau.c" ~ JuliaBUGS.dgamma(0.001, 0.001)
    
        alpha = Vector{Real}(undef, N)
        beta = Vector{Real}(undef, N)
        mu = Matrix{Real}(undef, N, T)
    
        for i in 1:N
            alpha[i] ~ JuliaBUGS.dnorm(var"alpha.c", var"alpha.tau")
            beta[i] ~ JuliaBUGS.dnorm(var"beta.c", var"beta.tau")
    
            for j in 1:T
                mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
                Y[i, j] ~ JuliaBUGS.dnorm(mu[i, j], var"tau.c")
            end
        end
    
        sigma = 1 / sqrt(var"tau.c")
        alpha0 = var"alpha.c" - xbar * var"beta.c"
    
        return alpha0, sigma
    end

end
