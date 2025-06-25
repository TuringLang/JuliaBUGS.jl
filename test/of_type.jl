using Test

include("../src/of_type.jl")

@testset "@of macro tests" begin
    @testset "Basic constant syntax" begin
        # Test Int constant
        T1 = of(Int; constant=true)
        @test T1 == OfConstantWrapper{OfInt{Nothing,Nothing}}
        @test string(T1) == "of(Int; constant=true)"

        # Test Real constant
        T2 = of(Real; constant=true)
        @test T2 == OfConstantWrapper{OfReal{Nothing,Nothing}}
        @test string(T2) == "of(Real; constant=true)"

        # Test non-constant versions
        T3 = of(Int)
        @test T3 == OfInt{Nothing,Nothing}

        T4 = of(Real, 0, 10)
        @test T4 == OfReal{Val{0},Val{10}}

        # Test that constant=true is not allowed for Array
        @test_throws ErrorException of(Array, 10; constant=true)
        @test_throws ErrorException of(Array, Float64, 5, 5; constant=true)
    end

    @testset "Simple @of macro" begin
        # Test basic usage
        T = @of(mu = of(Real), sigma = of(Real, 0, nothing), data = of(Array, 10))

        @test T <: OfNamedTuple
        names = get_names(T)
        @test names == (:mu, :sigma, :data)

        types = get_types(T)
        @test types.parameters[1] == OfReal{Nothing,Nothing}
        @test types.parameters[2] == OfReal{Val{0},Nothing}
        @test types.parameters[3] == OfArray{Float64,1,(10,)}
    end

    @testset "@of with constants and references" begin
        # Test with constant dimensions
        T = @of(
            rows = of(Int; constant=true),
            cols = of(Int; constant=true),
            data = of(Array, rows, cols)
        )

        @test T <: OfNamedTuple
        names = get_names(T)
        @test names == (:rows, :cols, :data)

        types = get_types(T)
        @test types.parameters[1] == OfConstantWrapper{OfInt{Nothing,Nothing}}
        @test types.parameters[2] == OfConstantWrapper{OfInt{Nothing,Nothing}}
        @test types.parameters[3] == OfArray{Float64,2,(:rows, :cols)}
    end

    @testset "@of with expressions" begin
        # Test with expression in dimension - currently not supported
        # The macro passes expressions as-is to of(), which doesn't handle them
        # This would require enhancing the of() function to handle expressions
        @test_skip begin
            T = @of(n = of(Int; constant=true), data = of(Array, n + 1, 2 * n))

            T <: OfNamedTuple
        end
    end

    @testset "Concrete type creation" begin
        # Define type with symbolic dimensions
        MatrixType = @of(
            rows = of(Int; constant=true),
            cols = of(Int; constant=true),
            data = of(Array, rows, cols)
        )

        # Create concrete type
        ConcreteType = MatrixType(; rows=3, cols=4)

        # Check that constants are removed and dimensions resolved
        names = get_names(ConcreteType)
        @test names == (:data,)  # rows and cols should be removed

        types = get_types(ConcreteType)
        @test types.parameters[1] == OfArray{Float64,2,(3, 4)}
    end

    @testset "rand and zero with constants" begin
        # Define type with constants
        T = @of(n = of(Int; constant=true), data = of(Array, n))

        # Test rand with keyword arguments
        val = rand(T; n=5)
        @test haskey(val, :data)
        @test size(val.data) == (5,)

        # Test zero with keyword arguments
        val = zero(T; n=3)
        @test haskey(val, :data)
        @test size(val.data) == (3,)
        @test all(val.data .== 0.0)
    end

    @testset "flatten/unflatten preserves array types" begin
        # Test that array element types are preserved
        T = @of(
            rows = of(Int; constant=true),
            cols = of(Int; constant=true),
            data = of(Array, rows, cols)
        )
        ConcreteType = T(; rows=2, cols=3)

        # Create test data
        original = (data=rand(Float64, 2, 3),)

        # Flatten and unflatten
        flat = flatten(ConcreteType, original)
        reconstructed = unflatten(ConcreteType, flat)

        # Check that type is preserved
        @test typeof(reconstructed.data) == typeof(original.data)
        @test typeof(reconstructed.data) == Matrix{Float64}
        @test reconstructed.data ≈ original.data
    end
end

@testset "Symbolic bounds tests" begin
    @testset "Basic symbolic bounds" begin
        # Test creating types with symbolic bounds
        T1 = of(Real, :lower, :upper)
        @test T1 == OfReal{SymbolicRef{:lower},SymbolicRef{:upper}}
        @test string(T1) == "of(Real, lower, upper)"

        # Test with one symbolic bound
        T2 = of(Real, 0, :max_val)
        @test T2 == OfReal{Val{0},SymbolicRef{:max_val}}
        @test string(T2) == "of(Real, 0, max_val)"

        # Test with constant wrapper
        T3 = of(Real, :min, :max; constant=true)
        @test T3 == OfConstantWrapper{OfReal{SymbolicRef{:min},SymbolicRef{:max}}}
        # Note: Julia's default printing adds colons to symbols in type parameters
        # Our show method correctly removes them for the wrapped type
    end

    @testset "Symbolic bounds in named tuples" begin
        # Use @of macro instead of of((;...))
        T = @of(
            lower_bound = of(Real, 0, nothing),
            upper_bound = of(Real, lower_bound, nothing),
            param = of(Real, lower_bound, upper_bound),
        )

        types = get_types(T)
        @test types.parameters[1] == OfReal{Val{0},Nothing}
        @test types.parameters[2] == OfReal{SymbolicRef{:lower_bound},Nothing}
        @test types.parameters[3] ==
            OfReal{SymbolicRef{:lower_bound},SymbolicRef{:upper_bound}}
    end

    @testset "@of macro with symbolic bounds" begin
        # Test that the macro correctly converts field references to symbols
        Schema = @of(
            min_val = of(Real, 0, 10),
            max_val = of(Real, min_val, 100),
            param = of(Real, min_val, max_val)
        )

        types = get_types(Schema)
        @test types.parameters[1] == OfReal{Val{0},Val{10}}
        @test types.parameters[2] == OfReal{SymbolicRef{:min_val},Val{100}}
        @test types.parameters[3] == OfReal{SymbolicRef{:min_val},SymbolicRef{:max_val}}
    end

    @testset "Symbolic bounds with constants" begin
        Schema = @of(
            lower = of(Real, 0, nothing; constant=true),
            upper = of(Real, lower, nothing; constant=true),
            x = of(Real, lower, upper)
        )

        types = get_types(Schema)
        @test types.parameters[1] == OfConstantWrapper{OfReal{Val{0},Nothing}}
        @test types.parameters[2] == OfConstantWrapper{OfReal{SymbolicRef{:lower},Nothing}}
        @test types.parameters[3] == OfReal{SymbolicRef{:lower},SymbolicRef{:upper}}
    end

    @testset "Concrete type creation with symbolic resolution" begin
        # Define schema with symbolic bounds
        Schema = @of(
            min_bound = of(Real; constant=true),
            max_bound = of(Real; constant=true),
            value = of(Real, min_bound, max_bound)
        )

        # Create concrete type by providing constants
        ConcreteType = Schema(; min_bound=0.0, max_bound=1.0)

        # The constants should be removed and bounds should be resolved
        names = get_names(ConcreteType)
        @test names == (:value,)

        types = get_types(ConcreteType)
        # This should resolve to concrete bounds
        @test types.parameters[1] == OfReal{Val{0.0},Val{1.0}}
    end

    @testset "Validation with symbolic bounds" begin
        # This is a forward-looking test - validation with runtime resolution
        Schema = @of(
            threshold = of(Real, 0, nothing; constant=true), value = of(Real, 0, threshold)
        )

        # When we provide threshold=10, value should be bounded by [0, 10]
        concrete = Schema(; threshold=10.0, value=5.0)
        @test concrete.value == 5.0

        # Should throw because value > threshold
        @test_throws ErrorException Schema(threshold=10.0, value=15.0)
    end
end
