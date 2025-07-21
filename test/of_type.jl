using Test

include("../src/of_type.jl")

@testset "Basic type creation" begin
    @testset "Simple type creation" begin
        # Test basic Int and Real types
        @test of(Int) == OfInt{Nothing,Nothing}
        @test of(Int, 0, 10) == OfInt{0,10}
        @test of(Real) == OfReal{Float64,Nothing,Nothing}
        @test of(Real, 0.0, 1.0) == OfReal{Float64,0.0,1.0}

        # Test array types
        @test of(Array, 5) == OfArray{Float64,1,Tuple{5}}
        @test of(Array, 3, 4) == OfArray{Float64,2,Tuple{3,4}}
        @test of(Array, Int, 2, 2) == OfArray{Int,2,Tuple{2,2}}
    end

    @testset "Symbolic bounds" begin
        # Test creating types with symbolic bounds
        T1 = of(Real, :lower, :upper)
        @test T1 == OfReal{Float64,SymbolicRef{:lower},SymbolicRef{:upper}}

        T2 = of(Int, 0, :max)
        @test T2 == OfInt{0,SymbolicRef{:max}}

        # Test with constants
        T3 = of(Real, :min, :max; constant=true)
        @test T3 == OfConstantWrapper{OfReal{Float64,SymbolicRef{:min},SymbolicRef{:max}}}
    end

    @testset "Explicit float types" begin
        # Test Float64
        @test of(Float64) == OfReal{Float64,Nothing,Nothing}
        @test of(Float64, 0.0, 1.0) == OfReal{Float64,0.0,1.0}
        @test of(Float64; constant=true) ==
            OfConstantWrapper{OfReal{Float64,Nothing,Nothing}}

        # Test Float32
        @test of(Float32) == OfReal{Float32,Nothing,Nothing}
        @test of(Float32, -1.0f0, 1.0f0) == OfReal{Float32,-1.0f0,1.0f0}
        @test of(Float32; constant=true) ==
            OfConstantWrapper{OfReal{Float32,Nothing,Nothing}}

        # Test that of(Real) defaults to Float64
        @test of(Real) == OfReal{Float64,Nothing,Nothing}

        # Test rand returns correct types
        @test rand(of(Float64)) isa Float64
        @test rand(of(Float32)) isa Float32
        @test rand(of(Real)) isa Float64  # defaults to Float64

        # Test zero returns correct types
        @test zero(of(Float64)) isa Float64
        @test zero(of(Float32)) isa Float32
        @test zero(of(Real)) isa Float64

        # Test with bounds
        val64 = rand(of(Float64, 0.0, 1.0))
        @test val64 isa Float64
        @test 0.0 <= val64 <= 1.0

        val32 = rand(of(Float32, -1.0f0, 1.0f0))
        @test val32 isa Float32
        @test -1.0f0 <= val32 <= 1.0f0
    end
end

@testset "@of macro tests" begin
    @testset "Basic constant syntax" begin
        # Test Int constant
        T1 = of(Int; constant=true)
        @test T1 == OfConstantWrapper{OfInt{Nothing,Nothing}}
        @test string(T1) == "of(Int; constant=true)"

        # Test Real constant
        T2 = of(Real; constant=true)
        @test T2 == OfConstantWrapper{OfReal{Float64,Nothing,Nothing}}
        @test string(T2) == "of(Real; constant=true)"

        # Test non-constant versions
        T3 = of(Int)
        @test T3 == OfInt{Nothing,Nothing}

        T4 = of(Real, 0, 10)
        @test T4 == OfReal{Float64,0,10}

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
        @test types.parameters[1] == OfReal{Float64,Nothing,Nothing}
        @test types.parameters[2] == OfReal{Float64,0,Nothing}
        @test types.parameters[3] == OfArray{Float64,1,Tuple{10}}
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
        @test types.parameters[3] == OfArray{Float64,2,Tuple{:rows,:cols}}
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

    @testset "@of with float types" begin
        # Test using explicit float types in @of macro
        T = @of(
            f64_val = of(Float64),
            f32_val = of(Float32, 0.0f0, 1.0f0),
            real_val = of(Real; constant=true),
            f64_array = of(Array, Float64, 3),
            f32_array = of(Array, Float32, 2, 2)
        )

        types = get_types(T)
        @test types.parameters[1] == OfReal{Float64,Nothing,Nothing}
        @test types.parameters[2] == OfReal{Float32,0.0f0,1.0f0}
        @test types.parameters[3] == OfConstantWrapper{OfReal{Float64,Nothing,Nothing}}
        @test types.parameters[4] == OfArray{Float64,1,Tuple{3}}
        @test types.parameters[5] == OfArray{Float32,2,Tuple{2,2}}

        # Test instance creation preserves types
        instance = T(; real_val=5.0)
        @test instance.f64_val isa Float64
        @test instance.f32_val isa Float32
        @test instance.f64_array isa Vector{Float64}
        @test instance.f32_array isa Matrix{Float32}
    end

    @testset "Concrete instance creation" begin
        # Define type with symbolic dimensions
        MatrixType = @of(
            rows = of(Int; constant=true),
            cols = of(Int; constant=true),
            data = of(Array, rows, cols)
        )

        # Create instance with constants provided
        instance = MatrixType(; rows=3, cols=4)

        # Check that we get an instance with only data field (constants eliminated)
        @test instance isa NamedTuple
        @test keys(instance) == (:data,)
        @test instance.data isa Matrix{Float64}
        @test size(instance.data) == (3, 4)
        @test all(instance.data .== 0.0)  # Should default to zero

        # Create instance with data provided
        test_data = rand(3, 4)
        instance2 = MatrixType(; rows=3, cols=4, data=test_data)
        @test instance2.data ≈ test_data
    end

    @testset "rand and zero with constants" begin
        # Define type with constants
        T = @of(n = of(Int; constant=true), data = of(Array, n))

        # Test rand with concrete type
        CT = of(T; n=5)
        val = rand(CT)
        @test haskey(val, :data)
        @test size(val.data) == (5,)

        # Test zero with concrete type
        CT2 = of(T; n=3)
        val = zero(CT2)
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
        ConcreteType = of(T; rows=2, cols=3)

        # Create test data - only data field since constants are eliminated
        original = (data=rand(Float64, 2, 3),)

        # Flatten and unflatten
        flat = flatten(ConcreteType, original)
        reconstructed = unflatten(ConcreteType, flat)

        # Check that data field is preserved
        @test typeof(reconstructed.data) == typeof(original.data)
        @test typeof(reconstructed.data) == Matrix{Float64}
        @test reconstructed.data ≈ original.data
    end

    @testset "flatten/unflatten with concrete types" begin
        # Test flatten/unflatten with concrete types
        T = @of(
            rows = of(Int; constant=true),
            cols = of(Int; constant=true),
            scale = of(Real, 0.1, 10.0),
            data = of(Array, rows, cols)
        )

        # Create instance
        instance = T(; rows=3, cols=2)
        @test instance isa NamedTuple
        @test keys(instance) == (:scale, :data)
        @test size(instance.data) == (3, 2)

        # Create concrete type first
        CT = of(T; rows=3, cols=2)

        # Flatten using the concrete type
        flat = flatten(CT, instance)
        @test length(flat) == 7  # 1 scale + 6 data elements

        # Unflatten using the concrete type
        reconstructed = unflatten(CT, flat)
        @test reconstructed.scale ≈ instance.scale
        @test reconstructed.data ≈ instance.data

        # Test with different data
        instance2 = (scale=2.5, data=rand(3, 2))
        flat2 = flatten(CT, instance2)
        reconstructed2 = unflatten(CT, flat2)
        @test reconstructed2.scale ≈ 2.5
        @test reconstructed2.data ≈ instance2.data
    end
end

@testset "Symbolic bounds tests" begin
    @testset "Symbolic references in @of macro" begin
        # Test that the @of macro properly converts field references to symbolic types
        T = @of(min = of(Real, 0, 10), max = of(Real, 20, 30), value = of(Real, min, max))

        types = get_types(T)
        # The 'value' field should have symbolic references to min and max
        @test types.parameters[3] == OfReal{Float64,SymbolicRef{:min},SymbolicRef{:max}}
    end

    @testset "Symbolic bounds in named tuples" begin
        # Use @of macro instead of of((;...))
        T = @of(
            lower_bound = of(Real, 0, nothing),
            upper_bound = of(Real, lower_bound, nothing),
            param = of(Real, lower_bound, upper_bound),
        )

        types = get_types(T)
        @test types.parameters[1] == OfReal{Float64,0,Nothing}
        @test types.parameters[2] == OfReal{Float64,SymbolicRef{:lower_bound},Nothing}
        @test types.parameters[3] ==
            OfReal{Float64,SymbolicRef{:lower_bound},SymbolicRef{:upper_bound}}
    end

    @testset "@of macro with symbolic bounds" begin
        # Test that the macro correctly converts field references to symbols
        Schema = @of(
            min_val = of(Real, 0, 10),
            max_val = of(Real, min_val, 100),
            param = of(Real, min_val, max_val)
        )

        types = get_types(Schema)
        @test types.parameters[1] == OfReal{Float64,0,10}
        @test types.parameters[2] == OfReal{Float64,SymbolicRef{:min_val},100}
        @test types.parameters[3] ==
            OfReal{Float64,SymbolicRef{:min_val},SymbolicRef{:max_val}}
    end

    @testset "Symbolic bounds with constants" begin
        Schema = @of(
            lower = of(Real, 0, nothing; constant=true),
            upper = of(Real, lower, nothing; constant=true),
            x = of(Real, lower, upper)
        )

        types = get_types(Schema)
        @test types.parameters[1] == OfConstantWrapper{OfReal{Float64,0,Nothing}}
        @test types.parameters[2] ==
            OfConstantWrapper{OfReal{Float64,SymbolicRef{:lower},Nothing}}
        @test types.parameters[3] == OfReal{Float64,SymbolicRef{:lower},SymbolicRef{:upper}}
    end

    @testset "Concrete instance creation with symbolic resolution" begin
        # Define schema with symbolic bounds
        Schema = @of(
            min_bound = of(Real; constant=true),
            max_bound = of(Real; constant=true),
            value = of(Real, min_bound, max_bound)
        )

        # Create instance by providing constants
        instance = Schema(; min_bound=0.0, max_bound=1.0)

        # The instance should only have the value field (constants eliminated)
        @test instance isa NamedTuple
        @test keys(instance) == (:value,)
        @test instance.value == 0.0  # Should default to lower bound

        # Create instance with explicit value
        instance2 = Schema(; min_bound=0.0, max_bound=1.0, value=0.5)
        @test instance2.value == 0.5
    end

    @testset "Validation with symbolic bounds" begin
        # This is a forward-looking test - validation with runtime resolution
        @test_skip begin
            Schema = @of(
                threshold = of(Real, 0, nothing; constant=true),
                value = of(Real, 0, threshold)
            )

            # Create concrete type first
            ConcreteSchema = Schema(; threshold=10.0)

            # Now create instances with the concrete type
            instance = ConcreteSchema(; threshold=10.0, value=5.0)
            @test instance.value == 5.0
            @test instance.threshold == 10.0

            # Should throw because value > threshold
            @test_throws ErrorException ConcreteSchema(threshold=10.0, value=15.0)
        end
    end
end

@testset "Constant Elimination After Concretization" begin
    # Basic constant elimination
    @testset "Basic elimination" begin
        T = @of(
            n = of(Int; constant=true), m = of(Int; constant=true), data = of(Array, n, m)
        )

        # Concretize with constant values
        CT = of(T; n=3, m=4)

        # Only non-constant fields should remain
        @test get_names(CT) == (:data,)

        # Check the resolved type
        types = get_types(CT)
        @test types.parameters[1] == of(Array, 3, 4)

        # Should be able to create instances
        instance = rand(CT)
        @test instance isa NamedTuple
        @test !haskey(instance, :n)
        @test !haskey(instance, :m)
        @test haskey(instance, :data)
        @test size(instance.data) == (3, 4)

        # Length should only include data field
        @test length(CT) == 12  # 3×4 array
    end

    # Constants with bounds
    @testset "Constants with bounds" begin
        T = @of(
            lower = of(Int, 1, 10; constant=true),
            upper = of(Int, 50, 100; constant=true),
            value = of(Real, lower, upper)
        )

        CT = of(T; lower=5, upper=75)

        # Only value field should remain with resolved bounds
        types = get_types(CT)
        @test get_names(CT) == (:value,)
        @test types.parameters[1] == of(Real, 5, 75)
    end

    # Partial concretization
    @testset "Partial concretization" begin
        T = @of(
            a = of(Int; constant=true), b = of(Int; constant=true), data = of(Array, a, b)
        )

        # Only provide value for 'a'
        CT = of(T; a=10)

        names = get_names(CT)
        types = get_types(CT)
        # 'a' is eliminated, 'b' still wrapped as constant, data uses concrete 'a'
        @test :a ∉ names
        @test :b ∈ names
        @test :data ∈ names

        b_idx = findfirst(==(Symbol("b")), names)
        @test types.parameters[b_idx] <: OfConstantWrapper

        data_idx = findfirst(==(Symbol("data")), names)
        @test types.parameters[data_idx] == of(Array, 10, :b)
    end

    # Nested structures
    @testset "Nested structures" begin
        InnerT = @of(size = of(Int; constant=true), values = of(Array, size))

        OuterT = @of(n = of(Int; constant=true), inner = InnerT)

        CT = of(OuterT; n=5, size=3)

        # n should be eliminated at outer level
        outer_names = get_names(CT)
        @test :n ∉ outer_names
        @test :inner ∈ outer_names

        outer_types = get_types(CT)
        inner_type = outer_types.parameters[1]

        # size should be eliminated at inner level
        inner_names = get_names(inner_type)
        @test :size ∉ inner_names
        @test :values ∈ inner_names

        inner_types = get_types(inner_type)
        @test inner_types.parameters[1] == of(Array, 3)
    end

    # Symbolic dimension checking
    @testset "Symbolic dimension checking" begin
        T = @of(const_field = of(Int; constant=true), regular_field = of(Real, 0, 1))

        @test has_symbolic_dims(T) == true

        CT = of(T; const_field=42)
        @test has_symbolic_dims(CT) == false

        # const_field should be eliminated
        @test get_names(CT) == (:regular_field,)
    end
end

@testset "Multi-hop constant dependencies" begin
    @testset "Chain dependencies" begin
        T = @of(
            a = of(Int, 1, 10; constant=true),
            b = of(Int, a, 20; constant=true),
            c = of(Int, b, 30; constant=true),
            data = of(Array, c, c)
        )

        # Concretize with all values
        CT = of(T; a=5, b=10, c=15)

        # All constants should be eliminated, only data remains
        @test get_names(CT) == (:data,)
        types = get_types(CT)
        @test types.parameters[1] == of(Array, 15, 15)
    end

    @testset "Expression dependencies" begin
        T = @of(
            base = of(Int, 2, 5; constant=true),
            width = of(Int, base, base * 2; constant=true),
            height = of(Int, base, base * 3; constant=true),
            volume = of(Array, width, height, base)
        )

        CT = of(T; base=3, width=5, height=7)

        # All constants should be eliminated, only volume remains
        @test get_names(CT) == (:volume,)
        types = get_types(CT)
        @test types.parameters[1] == of(Array, 5, 7, 3)
    end
end

@testset "Type operations" begin
    @testset "length calculation" begin
        # Test length for basic types
        @test length(of(Int)) == 1
        @test length(of(Real)) == 1
        @test length(of(Array, 5)) == 5
        @test length(of(Array, 3, 4)) == 12
        @test length(of(Array, Int, 2, 3, 4)) == 24

        # Test length for named tuples
        T = @of(a = of(Int), b = of(Real), c = of(Array, 3))
        @test length(T) == 5  # 1 + 1 + 3

        # Test length with constants eliminated
        T2 = @of(n = of(Int; constant=true), data = of(Array, n))
        CT = of(T2; n=10)
        @test length(CT) == 10  # only data field remains (n is eliminated)
    end

    @testset "rand generation" begin
        # Test rand for basic types
        @test rand(of(Int, 1, 10)) isa Int
        @test rand(of(Real, 0.0, 1.0)) isa Float64
        arr = rand(of(Array, 5, 3))
        @test arr isa Matrix{Float64}
        @test size(arr) == (5, 3)

        # Test rand for named tuples
        T = @of(x = of(Real), y = of(Int, 0, 100), z = of(Array, 2, 2))
        instance = rand(T)
        @test instance isa NamedTuple
        @test haskey(instance, :x) && instance.x isa Float64
        @test haskey(instance, :y) && instance.y isa Int
        @test haskey(instance, :z) && instance.z isa Matrix{Float64}
    end

    @testset "zero generation" begin
        # Test zero for basic types
        @test zero(of(Int)) == 0
        @test zero(of(Real)) == 0.0
        arr = zero(of(Array, 3, 2))
        @test arr isa Matrix{Float64}
        @test all(arr .== 0.0)

        # Test zero for named tuples
        T = @of(a = of(Int), b = of(Real), c = of(Array, 2))
        instance = zero(T)
        @test instance.a == 0
        @test instance.b == 0.0
        @test all(instance.c .== 0.0)
    end

    @testset "flatten/unflatten" begin
        # Test with mixed types
        T = @of(
            int_val = of(Int),
            real_val = of(Real),
            vec = of(Array, 3),
            mat = of(Array, 2, 2)
        )

        original = (int_val=42, real_val=3.14, vec=[1.0, 2.0, 3.0], mat=[4.0 5.0; 6.0 7.0])
        flat = flatten(T, original)
        reconstructed = unflatten(T, flat)

        @test reconstructed.int_val == original.int_val
        @test reconstructed.real_val ≈ original.real_val
        @test reconstructed.vec ≈ original.vec
        @test reconstructed.mat ≈ original.mat

        # Test that flattening is consistent
        @test length(flat) == length(T)
    end

    @testset "flatten/unflatten with float types" begin
        # Test that float types are preserved through flatten/unflatten
        T = @of(
            f64 = of(Float64, 0.0, 1.0),
            f32 = of(Float32, -1.0f0, 1.0f0),
            f64_vec = of(Array, Float64, 3),
            f32_mat = of(Array, Float32, 2, 2)
        )

        original = (
            f64=0.5, f32=0.25f0, f64_vec=[0.1, 0.2, 0.3], f32_mat=Float32[0.1 0.2; 0.3 0.4]
        )

        flat = flatten(T, original)
        reconstructed = unflatten(T, flat)

        # Check types are preserved
        @test reconstructed.f64 isa Float64
        @test reconstructed.f32 isa Float32
        @test reconstructed.f64_vec isa Vector{Float64}
        @test reconstructed.f32_mat isa Matrix{Float32}

        # Check values
        @test reconstructed.f64 ≈ original.f64
        @test reconstructed.f32 ≈ original.f32
        @test reconstructed.f64_vec ≈ original.f64_vec
        @test reconstructed.f32_mat ≈ original.f32_mat
    end
end

@testset "Array type specifications" begin
    @testset "Different element types" begin
        # Test Int arrays
        T1 = of(Array, Int, 5)
        @test get_element_type(T1) == Int
        @test get_ndims(T1) == 1
        @test get_dims(T1) == (5,)

        # Test Bool arrays
        T2 = of(Array, Bool, 3, 3)
        @test get_element_type(T2) == Bool
        @test get_ndims(T2) == 2
        @test get_dims(T2) == (3, 3)

        # Test that default is Float64
        T3 = of(Array, 10)
        @test get_element_type(T3) == Float64
    end

    @testset "Symbolic dimensions in arrays" begin
        T = @of(
            rows = of(Int; constant=true),
            cols = of(Int; constant=true),
            matrix = of(Array, rows, cols),
            tensor = of(Array, rows, cols, 3)
        )

        types = get_types(T)
        mat_type = types.parameters[3]
        @test get_dims(mat_type) == (:rows, :cols)

        tensor_type = types.parameters[4]
        @test get_dims(tensor_type) == (:rows, :cols, 3)

        # Test concretization
        CT = of(T; rows=2, cols=4)
        # rows and cols are eliminated, only matrix and tensor remain
        @test get_names(CT) == (:matrix, :tensor)
        ct_types = get_types(CT)
        @test get_dims(ct_types.parameters[1]) == (2, 4)
        @test get_dims(ct_types.parameters[2]) == (2, 4, 3)
    end
end

@testset "Constructor with default_value" begin
    @testset "Basic default_value usage" begin
        # Define a simple type
        T = @of(
            rows = of(Int; constant=true),
            cols = of(Int; constant=true),
            scale = of(Real, 0.1, 10.0),
            data = of(Array, rows, cols)
        )

        # Test using zero() as default (original behavior)
        instance1 = T(; rows=3, cols=2)
        @test instance1.scale == 0.1  # Should default to lower bound
        @test all(instance1.data .== 0.0)

        # Test using custom default_value
        instance2 = T(1.5; rows=3, cols=2)
        @test instance2.scale == 1.5
        @test all(instance2.data .== 1.5)

        # Test with missing as default_value
        instance3 = T(missing; rows=3, cols=2)
        @test instance3.scale === missing
        @test all(instance3.data .=== missing)

        # Test partial override with default_value
        instance4 = T(2.0; rows=3, cols=2, scale=5.0)
        @test instance4.scale == 5.0  # Explicitly provided
        @test all(instance4.data .== 2.0)  # Uses default_value
    end

    @testset "Default value validation" begin
        # Type with bounded values
        T = @of(n = of(Int; constant=true), bounded = of(Real, 0, 10), data = of(Array, n))

        # Valid default_value within bounds
        instance = T(5.0; n=3)
        @test instance.bounded == 5.0
        @test all(instance.data .== 5.0)

        # Invalid default_value outside bounds should throw
        @test_throws ErrorException T(15.0; n=3)  # 15.0 > upper bound 10
        @test_throws ErrorException T(-5.0; n=3)  # -5.0 < lower bound 0
    end

    @testset "Different types with default_value" begin
        T = @of(
            size = of(Int; constant=true),
            int_val = of(Int, 1, 100),
            real_val = of(Real),
            vec = of(Array, size),
            mat = of(Array, size, size)
        )

        # Test with integer default
        instance1 = T(42; size=2)
        @test instance1.int_val == 42
        @test instance1.real_val == 42.0
        @test all(instance1.vec .== 42.0)
        @test all(instance1.mat .== 42.0)

        # Test with float default
        instance2 = T(3.14; size=2)
        @test instance2.int_val == 3  # Should round to Int
        @test instance2.real_val ≈ 3.14
        @test all(instance2.vec .≈ 3.14)
        @test all(instance2.mat .≈ 3.14)
    end

    @testset "Nested structures with default_value" begin
        # For nested structures, we need a simpler example
        # The inner structure's constants should be handled at the outer level
        OuterT = @of(n = of(Int; constant=true), scale = of(Real), vec = of(Array, n))

        # Test default_value propagation
        instance = OuterT(7.0; n=5)
        @test instance.scale == 7.0
        @test instance.vec isa Vector{Float64}
        @test length(instance.vec) == 5
        @test all(instance.vec .== 7.0)
    end

    @testset "Type stability of default_value" begin
        T = @of(n = of(Int; constant=true), data = of(Array, n))

        # The two constructor methods should be type-stable
        CT = of(T; n=5)

        # Method 1: no positional argument
        @inferred NamedTuple{(:data,),Tuple{Vector{Float64}}} T(; n=5)

        # Method 2: with positional default_value
        @inferred NamedTuple{(:data,),Tuple{Vector{Float64}}} T(1.0; n=5)
    end
end

@testset "Edge cases and error handling" begin
    @testset "Invalid bounds" begin
        # Test that invalid bounds are caught during validation
        T = @of(value = of(Real, 0, 10))
        @test_throws ErrorException T(value=15.0)  # value > upper bound
        @test_throws ErrorException T(value=-5.0)  # value < lower bound
    end

    @testset "Missing required constants" begin
        T = @of(n = of(Int; constant=true), data = of(Array, n))

        # Should throw when trying to use without providing constant
        @test_throws ErrorException rand(T)
        @test_throws ErrorException zero(T)

        # Should throw when trying to create instance without providing constant
        @test_throws ErrorException T()
        @test_throws ErrorException T(data=rand(5))
    end

    @testset "Type display" begin
        # Test string representations
        @test string(of(Int)) == "of(Int)"
        @test string(of(Int, 0, 10)) == "of(Int, 0, 10)"
        @test string(of(Real, 0.0, nothing)) == "of(Float64, 0.0, nothing)"
        @test string(of(Float64, 0.0, nothing)) == "of(Float64, 0.0, nothing)"
        @test string(of(Float32, 0.0f0, nothing)) == "of(Float32, 0.0, nothing)"
        @test string(of(Array, 5)) == "of(Array, 5)"
        @test string(of(Array, Float32, 3, 3)) == "of(Array, Float32, 3, 3)"

        # Test constant wrapper display
        @test string(of(Int; constant=true)) == "of(Int; constant=true)"
        @test string(of(Real, 0, 1; constant=true)) == "of(Real, 0, 1; constant=true)"
        @test string(of(Float64; constant=true)) == "of(Real; constant=true)"
        @test string(of(Float32; constant=true)) == "of(Float32; constant=true)"

        # Test that types without bounds don't show "nothing"
        T = @of(rows = of(Int), cols = of(Int), data = of(Array, 3, 4))
        str = string(T)
        @test occursin("rows = of(Int)", str)
        @test occursin("cols = of(Int)", str)
        @test !occursin("nothing", str)
    end

    @testset "Type inference from values" begin
        # Test that of(value) infers the correct type
        @test of(1.0) == of(Float64)
        @test of(1.0f0) == of(Float32)
        @test of(1) == of(Int)
        @test of(1//2) == of(Float64)  # Rationals default to Float64
        @test of(big(1.0)) == of(BigFloat)

        # Test arrays
        @test of([1.0, 2.0, 3.0]) == of(Array, Float64, 3)
        @test of(Float32[1.0, 2.0]) == of(Array, Float32, 2)
        @test of([1 2; 3 4]) == of(Array, Int, 2, 2)
    end
end
