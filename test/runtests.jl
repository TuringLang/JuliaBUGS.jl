using BangBang
using Bijectors
using Distributions
using DynamicPPL
using Graphs
using JuliaBUGS
using LogDensityProblems
using MetaGraphsNext
using Setfield
using Test
using UnPack
using Documenter

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