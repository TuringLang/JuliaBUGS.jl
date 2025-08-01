using Test

@testset "ProbabilisticGraphicalModels Tests" begin
    include("test_basic_operations.jl")
    include("test_sampling_independence.jl")
    include("test_bugs_integration.jl")
    include("test_marginalization.jl")
    include("test_dynamic_programming.jl")
end
