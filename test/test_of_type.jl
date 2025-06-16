using Test
using JuliaBUGS

@testset "OfType Tests" begin
    @testset "Basic Constructors" begin
        # Test array specifications
        @test JuliaBUGS.of(Array, 2, 3) isa JuliaBUGS.OfArray{Float64,2}
        @test JuliaBUGS.of(Array, Int, 2, 3) isa JuliaBUGS.OfArray{Int,2}

        # Test real specifications
        @test JuliaBUGS.of(Real) isa JuliaBUGS.OfReal
        @test JuliaBUGS.of(Real, 0, 10) isa JuliaBUGS.OfReal

        # Test named tuple specifications
        nt_spec = JuliaBUGS.of((a=Real, b=Array))
        @test nt_spec isa JuliaBUGS.OfNamedTuple
    end

    @testset "julia_type" begin
        @test JuliaBUGS.julia_type(JuliaBUGS.of(Array, 2, 3)) == Array{Float64,2}
        @test JuliaBUGS.julia_type(JuliaBUGS.of(Real)) == Float64
        @test JuliaBUGS.julia_type(JuliaBUGS.of((a=Real, b=Array))) ==
            NamedTuple{(:a, :b),Tuple{Float64,Array{Float64,1}}}
    end

    @testset "rand" begin
        # Test array generation
        arr_spec = JuliaBUGS.of(Array, 2, 3)
        arr = rand(arr_spec)
        @test arr isa Array{Float64,2}
        @test size(arr) == (2, 3)

        # Test bounded real generation
        bounded_spec = JuliaBUGS.of(Real, 5, 10)
        for _ in 1:100
            val = rand(bounded_spec)
            @test 5 <= val <= 10
        end

        # Test named tuple generation
        nt_spec = JuliaBUGS.of((a=Real, b=of(Array, 2)))
        nt = rand(nt_spec)
        @test nt isa NamedTuple{(:a, :b)}
        @test nt.a isa Float64
        @test nt.b isa Array{Float64,1}
        @test length(nt.b) == 2
    end

    @testset "zero" begin
        # Test array zeros
        arr_spec = JuliaBUGS.of(Array, 2, 3)
        arr = zero(arr_spec)
        @test all(arr .== 0)
        @test size(arr) == (2, 3)

        # Test bounded real zeros
        @test zero(JuliaBUGS.of(Real, 5, 10)) == 5.0
        @test zero(JuliaBUGS.of(Real, -10, -5)) == -5.0
        @test zero(JuliaBUGS.of(Real, -5, 5)) == 0.0

        # Test named tuple zeros
        nt_spec = JuliaBUGS.of((a=Real, b=of(Array, 2)))
        nt = zero(nt_spec)
        @test nt.a == 0.0
        @test all(nt.b .== 0)
    end

    @testset "validate" begin
        # Test array validation
        arr_spec = JuliaBUGS.of(Array, Int, 2, 2)
        @test JuliaBUGS.validate(arr_spec, [1 2; 3 4]) == [1 2; 3 4]
        @test_throws ErrorException JuliaBUGS.validate(arr_spec, [1, 2, 3])  # Wrong dimensions

        # Test bounded real validation
        bounded_spec = JuliaBUGS.of(Real, 0, 10)
        @test JuliaBUGS.validate(bounded_spec, 5) == 5.0
        @test_throws ErrorException JuliaBUGS.validate(bounded_spec, -1)
        @test_throws ErrorException JuliaBUGS.validate(bounded_spec, 11)

        # Test named tuple validation
        nt_spec = JuliaBUGS.of((a=Real, b=of(Array, 2)))
        @test JuliaBUGS.validate(nt_spec, (a=1, b=[2, 3])) == (a=1.0, b=[2.0, 3.0])
    end
end

@testset "Flatten and Unflatten" begin
    # Test from design doc: hierarchical linear model
    @testset "Hierarchical Model Example" begin
        # Define hierarchical model parameters
        params_spec = of((
            # Fixed effects
            mu0=of(Real),                      # Grand mean
            beta=of(Array, Float64, 3),        # Regression coefficients (3 covariates)

            # Variance components
            tau2=of(Real, 0, nothing),         # Between-school variance
            sigma2=of(Real, 0, nothing),       # Within-school variance

            # Random effects
            school_effects=of(Array, 10),       # School-specific intercepts (10 schools)
        ))

        # Create test values
        test_params = (
            mu0=75.0,
            beta=[2.1, -0.5, 1.3],
            tau2=25.0,
            sigma2=100.0,
            school_effects=randn(10) * 5,
        )

        # Validate parameters
        validated_params = JuliaBUGS.validate(params_spec, test_params)

        # Test flatten
        flat_params = JuliaBUGS.flatten(params_spec, validated_params)

        # Check correct number of parameters
        # 1 (mu0) + 3 (beta) + 1 (tau2) + 1 (sigma2) + 10 (school_effects) = 16
        @test length(flat_params) == 16

        # Check values are in correct order
        @test flat_params[1] == 75.0
        @test flat_params[2:4] == [2.1, -0.5, 1.3]
        @test flat_params[5] == 25.0
        @test flat_params[6] == 100.0
        @test flat_params[7:16] == vec(test_params.school_effects)

        # Test unflatten
        reconstructed = JuliaBUGS.unflatten(params_spec, flat_params)

        # Check reconstructed values match original
        @test reconstructed.mu0 == test_params.mu0
        @test reconstructed.beta == test_params.beta
        @test reconstructed.tau2 == test_params.tau2
        @test reconstructed.sigma2 == test_params.sigma2
        @test reconstructed.school_effects == test_params.school_effects

        # Test round trip with transformation
        new_flat = flat_params .* 0.9
        transformed_params = JuliaBUGS.unflatten(params_spec, new_flat)

        @test transformed_params.mu0 H test_params.mu0 * 0.9
        @test transformed_params.beta H test_params.beta .* 0.9
        @test transformed_params.tau2 H test_params.tau2 * 0.9
        @test transformed_params.sigma2 H test_params.sigma2 * 0.9
        @test transformed_params.school_effects H test_params.school_effects .* 0.9
    end

    @testset "Simple cases" begin
        # Test single array
        spec1 = of(Array, 2, 3)
        val1 = rand(2, 3)
        flat1 = JuliaBUGS.flatten(spec1, val1)
        @test length(flat1) == 6
        @test flat1 == vec(val1)
        reconstructed1 = JuliaBUGS.unflatten(spec1, flat1)
        @test reconstructed1 == val1

        # Test single real
        spec2 = of(Real, 0, 10)
        val2 = 5.5
        flat2 = JuliaBUGS.flatten(spec2, val2)
        @test length(flat2) == 1
        @test flat2[1] == 5.5
        reconstructed2 = JuliaBUGS.unflatten(spec2, flat2)
        @test reconstructed2 == 5.5

        # Test nested structure
        spec3 = of((a=of(Real), b=of((x=of(Array, 2), y=of(Real, 0, nothing)))))
        val3 = (a=1.0, b=(x=[2.0, 3.0], y=4.0))
        flat3 = JuliaBUGS.flatten(spec3, val3)
        @test length(flat3) == 4
        @test flat3 == [1.0, 2.0, 3.0, 4.0]
        reconstructed3 = JuliaBUGS.unflatten(spec3, flat3)
        @test reconstructed3.a == 1.0
        @test reconstructed3.b.x == [2.0, 3.0]
        @test reconstructed3.b.y == 4.0
    end

    @testset "Error cases" begin
        spec = of((a=of(Array, 2), b=of(Real)))

        # Not enough values
        @test_throws ErrorException JuliaBUGS.unflatten(spec, [1.0])

        # Too many values
        @test_throws ErrorException JuliaBUGS.unflatten(spec, [1.0, 2.0, 3.0, 4.0])

        # Bounds violation
        spec_bounded = of(Real, 0, 10)
        @test_throws ErrorException JuliaBUGS.unflatten(spec_bounded, [-1.0])
        @test_throws ErrorException JuliaBUGS.unflatten(spec_bounded, [11.0])
    end
end