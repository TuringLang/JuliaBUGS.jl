# Check if running directly (not through Pkg.test)
# When run through Pkg.test, the working directory is set to the test directory
if !endswith(pwd(), "/test") && !endswith(pwd(), "\\test")
    # Running directly, not through Pkg.test
    println("\nERROR: Do not run tests directly!\n")
    println("Tests must be run using Pkg.test with test_args.\n")
    println("Examples:")
    println("    using Pkg")
    println("    Pkg.test(test_args=[\"all\"])                    # Run all tests")
    println("    Pkg.test(test_args=[\"elementary\"])             # Run elementary tests")
    println("    Pkg.test(test_args=[\"model/abstractppl.jl\"])   # Run specific file")
    exit(1)
end

using Test

using ADTypes
using AbstractPPL
using Bijectors
using ChainRules # needed for `Bijectors.cholesky_lower`
using Distributions
using Documenter
using Graphs
using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BUGSPrimitives: mean
using LinearAlgebra
using LogDensityProblems
using LogDensityProblemsAD
using LogExpFunctions
using MacroTools
using MetaGraphsNext
using OrderedCollections
using Random
using Serialization
using StableRNGs

using AbstractMCMC
using AdvancedHMC
using AdvancedMH
using MCMCChains
using ReverseDiff

JuliaBUGS.@bugs_primitive Beta Bernoulli Categorical Exponential Gamma InverseGamma Normal Uniform LogNormal Poisson
JuliaBUGS.@bugs_primitive Diagonal Dirichlet LKJ MvNormal
JuliaBUGS.@bugs_primitive censored product_distribution truncated
JuliaBUGS.@bugs_primitive fill ones zeros
JuliaBUGS.@bugs_primitive sum mean sqrt

const TEST_GROUPS = OrderedDict{String,Function}(
    "elementary" => () -> begin
        Documenter.doctest(JuliaBUGS; manual=false)
        include("BUGSPrimitives/distributions.jl")
        include("BUGSPrimitives/functions.jl")
    end,
    "frontend" => () -> begin
        include("parser/bugs_macro.jl")
        include("parser/bugs_parser.jl")
        include("compiler_pass.jl")
        include("model_macro.jl")
        include("of_type.jl")
        include("of_model_integration.jl")
    end,
    "graphs" => () -> include("graphs.jl"),
    "compilation" => () -> begin
        include("model/utils.jl")
        include("model/bugsmodel.jl")
        include("source_gen.jl")
    end,
    "model_operations" => () -> begin
        include("model/abstractppl.jl")
    end,
    "log_density" => () -> begin
        include("model/evaluation.jl")
        include("model/auto_marginalization.jl")
        include("model/frontier_cache_hmm.jl")
    end,
    "inference" => () -> begin
        include("independent_mh.jl")
        include("ext/JuliaBUGSAdvancedHMCExt.jl")
        include("ext/JuliaBUGSMCMCChainsExt.jl")
    end,
    "inference_hmc" => () -> include("ext/JuliaBUGSAdvancedHMCExt.jl"),
    "inference_chains" => () -> include("ext/JuliaBUGSMCMCChainsExt.jl"),
    "inference_mh" => () -> include("independent_mh.jl"),
    "gibbs" => () -> include("gibbs.jl"),
    "parallel_sampling" => () -> include("parallel_sampling.jl"),
    "experimental" =>
        () -> include("experimental/ProbabilisticGraphicalModels/runtests.jl"),
)

function print_test_usage()
    println("""

    JuliaBUGS Test Runner Usage:
    ===========================

    Tests must be run using Pkg.test with test_args:

    Run all tests:
        Pkg.test(test_args=["all"])

    Run specific test groups:
        Pkg.test(test_args=["<group1>", "<group2>", ...])

    Run specific test files (must end with .jl):
        Pkg.test(test_args=["path/to/test.jl"])

    Available test groups:
        $(join(sort(collect(keys(TEST_GROUPS))), "\n        "))

    Examples:
        using Pkg
        Pkg.test(test_args=["all"])                    # Run all tests
        Pkg.test(test_args=["elementary"])             # Run elementary tests
        Pkg.test(test_args=["model_operations"])       # Run model operations tests
        Pkg.test(test_args=["model/abstractppl.jl"])   # Run specific file
        Pkg.test(test_args=["elementary", "graphs"])   # Run multiple groups
    """)
end

# Get test selection from command line arguments or environment variable
# No default - must be explicit
selected_items = String[]

if !isempty(ARGS)
    selected_items = ARGS
elseif haskey(ENV, "TEST_GROUP")
    # Support environment variable for CI
    selected_items = split(ENV["TEST_GROUP"], ",")
else
    println("\nERROR: No tests specified!\n")
    println(
        "You must specify what to test using Pkg.test(test_args=[...]) or TEST_GROUP environment variable\n",
    )
    print_test_usage()
    exit(1)  # Exit with error code
end

# Separate files from groups
test_files = String[]
test_groups = String[]
errors = String[]

for item in selected_items
    if item == "all" || haskey(TEST_GROUPS, item)
        # It's a valid test group
        push!(test_groups, item)
    elseif endswith(item, ".jl")
        # It's a file path - must end with .jl
        if isfile(joinpath(@__DIR__, item))
            push!(test_files, item)
        else
            push!(errors, "File not found: $item")
        end
    else
        # Invalid item - not a group and doesn't end with .jl
        push!(
            errors,
            "Invalid test specification: '$item' (must be a test group name or a .jl file)",
        )
    end
end

# Report all errors at once with helpful usage
if !isempty(errors)
    println("\nERROR: Invalid test arguments:")
    for err in errors
        println("  - $err")
    end
    print_test_usage()
    error("Test runner failed due to invalid arguments")
end

# Execute test groups
if "all" in test_groups
    @info "Running tests for ALL groups"
    for fn in values(TEST_GROUPS)
        fn()
    end
elseif !isempty(test_groups)
    @info "Running tests for groups: $(join(test_groups, ", "))"
    for g in test_groups
        TEST_GROUPS[g]()
    end
end

# Run individual test files
# Note: Files are included after all imports at the top, so they have access to all dependencies
if !isempty(test_files)
    @info "Running individual test files: $(join(test_files, ", "))"
    for file in test_files
        @testset "$(file)" begin
            include(file)
        end
    end
end
