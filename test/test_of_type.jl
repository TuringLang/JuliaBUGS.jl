using Test
using JuliaBUGS

@testset "of type system" begin
    @testset "Basic of construction" begin
        # Array types
        of_arr1 = of(Array, 3, 4)
        @test of_arr1 isa JuliaBUGS.OfArray{Any,2}
        @test of_arr1.dims == (3, 4)
        @test of_arr1.element_type == Any

        of_arr2 = of(Array, Float64, 2, 5)
        @test of_arr2 isa JuliaBUGS.OfArray{Float64,2}
        @test of_arr2.dims == (2, 5)
        @test of_arr2.element_type == Float64

        # Real types
        of_real1 = of(Real)
        @test of_real1 isa JuliaBUGS.OfReal
        @test isnothing(of_real1.lower)
        @test isnothing(of_real1.upper)

        of_real2 = of(Real, 0.0, 1.0)
        @test of_real2 isa JuliaBUGS.OfReal
        @test of_real2.lower == 0.0
        @test of_real2.upper == 1.0

        # Nested of types
        of_arr3 = of(Array, of(Real), 3, 3)
        @test of_arr3 isa JuliaBUGS.OfArray{Float64,2}
        @test of_arr3.dims == (3, 3)
    end

    @testset "Tuple and NamedTuple construction" begin
        # Tuple
        x = of(Array, 8)
        y = of(Array, Float64, 4, 3)
        w = of(Real, 0.0, 1.0)

        of_tuple = of((x, y, w))
        @test of_tuple isa JuliaBUGS.OfTuple
        @test length(of_tuple.types) == 3
        @test of_tuple.types[1] === x
        @test of_tuple.types[2] === y
        @test of_tuple.types[3] === w

        # NamedTuple
        of_nt = of((x=x, y=y, w=w))
        @test of_nt isa JuliaBUGS.OfNamedTuple{(:x, :y, :w)}
        @test length(of_nt.types) == 3
    end

    @testset "rand() for of types" begin
        # Array
        of_arr = of(Array, Float64, 3, 4)
        arr = rand(of_arr)
        @test arr isa Array{Float64,2}
        @test size(arr) == (3, 4)
        @test all(0 .<= arr .<= 1)

        # Real without bounds
        of_real = of(Real)
        val = rand(of_real)
        @test val isa Float64
        @test 0 <= val <= 1

        # Real with bounds
        of_real_bounded = of(Real, 10.0, 20.0)
        val_bounded = rand(of_real_bounded)
        @test val_bounded isa Float64
        @test 10.0 <= val_bounded <= 20.0

        # Tuple
        of_tuple = of((of(Array, 2, 2), of(Real)))
        tuple_val = rand(of_tuple)
        @test tuple_val isa Tuple
        @test length(tuple_val) == 2
        @test tuple_val[1] isa Array{Any,2}
        @test size(tuple_val[1]) == (2, 2)
        @test tuple_val[2] isa Float64

        # NamedTuple
        of_nt = of((x=of(Array, 3), y=of(Real, 0.0, 1.0)))
        nt_val = rand(of_nt)
        @test nt_val isa NamedTuple{(:x, :y)}
        @test nt_val.x isa Array{Any,1}
        @test length(nt_val.x) == 3
        @test 0.0 <= nt_val.y <= 1.0
    end

    @testset "zero() for of types" begin
        # Array
        of_arr = of(Array, Float64, 3, 4)
        arr = zero(of_arr)
        @test arr isa Array{Float64,2}
        @test size(arr) == (3, 4)
        @test all(arr .== 0.0)

        # Real without bounds
        of_real = of(Real)
        val = zero(of_real)
        @test val == 0.0

        # Real with positive lower bound
        of_real_pos = of(Real, 5.0, 10.0)
        val_pos = zero(of_real_pos)
        @test val_pos == 5.0

        # Real with negative upper bound
        of_real_neg = of(Real, -10.0, -5.0)
        val_neg = zero(of_real_neg)
        @test val_neg == -5.0

        # Tuple
        of_tuple = of((of(Array, 2, 2), of(Real)))
        tuple_val = zero(of_tuple)
        @test tuple_val isa Tuple
        @test all(tuple_val[1] .== 0.0)
        @test tuple_val[2] == 0.0

        # NamedTuple
        of_nt = of((x=of(Array, Int, 3), y=of(Real)))
        nt_val = zero(of_nt)
        @test nt_val isa NamedTuple{(:x, :y)}
        @test all(nt_val.x .== 0)
        @test nt_val.y == 0.0
    end

    @testset "Callable syntax" begin
        of_arr = of(Array, 2, 3)
        @test of_arr() == zero(of_arr)

        of_real = of(Real, 1.0, 2.0)
        @test of_real() == 1.0

        of_tuple = of((of(Array, 2), of(Real)))
        @test of_tuple() == zero(of_tuple)

        of_nt = of((x=of(Real), y=of(Array, 3)))
        @test of_nt() == zero(of_nt)
    end

    @testset "Type conversion" begin
        @test JuliaBUGS.julia_type(of(Array, 3, 4)) == Array{Any,2}
        @test JuliaBUGS.julia_type(of(Array, Float64, 2)) == Array{Float64,1}
        @test JuliaBUGS.julia_type(of(Real)) == Float64

        of_tuple = of((of(Array, 2), of(Real)))
        @test JuliaBUGS.julia_type(of_tuple) == Tuple{Array{Any,1},Float64}

        of_nt = of((x=of(Real), y=of(Array, Int, 3, 3)))
        @test JuliaBUGS.julia_type(of_nt) ==
            NamedTuple{(:x, :y),Tuple{Float64,Array{Int,2}}}
    end

    @testset "Show methods" begin
        @test string(of(Array, 3, 4)) == "of(Array, 3, 4)"
        @test string(of(Array, Float64, 2)) == "of(Array, Float64, 2)"
        @test string(of(Real)) == "of(Real)"
        @test string(of(Real, 0.0, 1.0)) == "of(Real, 0.0, 1.0)"
        @test string(of((of(Array, 2), of(Real)))) == "of((of(Array, 2), of(Real)))"
        @test string(of((x=of(Real), y=of(Array, 3)))) == "of((x=of(Real), y=of(Array, 3)))"
    end

    @testset "Vector and Dict types" begin
        # Vector construction
        ofv1 = of(Vector, Float64, 5)
        @test ofv1 isa JuliaBUGS.OfVector
        @test ofv1.length == 5
        @test ofv1.element_type == of(Float64)

        ofv2 = of(Vector, of(Array, 2, 2))
        @test ofv2 isa JuliaBUGS.OfVector
        @test isnothing(ofv2.length)

        # Dict construction
        ofd1 = of(Dict, Symbol, Float64)
        @test ofd1 isa JuliaBUGS.OfDict{Symbol}
        @test isnothing(ofd1.keys)

        ofd2 = of(Dict, String, of(Array, 3), ["a", "b", "c"])
        @test ofd2 isa JuliaBUGS.OfDict{String}
        @test ofd2.keys == ["a", "b", "c"]

        # rand for Vector and Dict
        v1 = rand(ofv1)
        @test v1 isa Vector{Float64}
        @test length(v1) == 5

        d1 = rand(ofd2)
        @test d1 isa Dict{String}
        @test keys(d1) == Set(["a", "b", "c"])
        @test all(v isa Array && length(v) == 3 for v in values(d1))

        # zero for Vector and Dict
        v0 = zero(ofv1)
        @test v0 isa Vector{Float64}
        @test length(v0) == 5
        @test all(v0 .== 0.0)

        d0 = zero(ofd2)
        @test d0 isa Dict{String}
        @test keys(d0) == Set(["a", "b", "c"])
        @test all(v isa Array && all(v .== 0.0) for v in values(d0))
    end

    @testset "Pytree utilities" begin
        # Test is_leaf
        @test JuliaBUGS.is_leaf(of(Real))
        @test JuliaBUGS.is_leaf(of(Array, 3, 4))
        @test !JuliaBUGS.is_leaf(of((of(Real), of(Array, 2))))
        @test !JuliaBUGS.is_leaf(of((x=of(Real), y=of(Array, 2))))
        @test !JuliaBUGS.is_leaf(of(Vector, Float64))
        @test !JuliaBUGS.is_leaf(of(Dict, Symbol, Float64))

        # Test tree_leaves
        simple = of(Real)
        @test JuliaBUGS.tree_leaves(simple) == [simple]

        tuple_type = of((of(Real), of(Array, 2, 3)))
        leaves = JuliaBUGS.tree_leaves(tuple_type)
        @test length(leaves) == 2
        @test leaves[1] isa JuliaBUGS.OfReal
        @test leaves[2] isa JuliaBUGS.OfArray

        nested = of((
            x=of(Array, 3),
            y=of((of(Real, 0, 1), of(Array, Float64, 2, 2))),
            z=of(Vector, of(Real), 5),
        ))
        leaves = JuliaBUGS.tree_leaves(nested)
        @test length(leaves) == 4  # Array, Real, Array, Real (in Vector)

        # Test tree_map
        doubled = JuliaBUGS.tree_map(tuple_type) do leaf
            if leaf isa JuliaBUGS.OfArray
                return of(Array, leaf.element_type, (leaf.dims .* 2)...)
            else
                return leaf
            end
        end
        @test doubled.types[2].dims == (4, 6)

        # Test flatten/unflatten
        complex_type = of((
            a=of(Real, 0, 1),
            b=of(Array, Float64, 3, 3),
            c=of(Vector, of(Array, 2, 2), 4),
            d=of(Dict, Symbol, of(Real), [:x, :y, :z]),
        ))

        leaves, structure = JuliaBUGS.flatten(complex_type)
        @test length(leaves) == 4  # Real, Array, Array (in Vector), Real (in Dict)

        reconstructed = JuliaBUGS.unflatten(leaves, structure)
        @test reconstructed isa JuliaBUGS.OfNamedTuple{(:a, :b, :c, :d)}
        @test reconstructed.types[1] isa JuliaBUGS.OfReal
        @test reconstructed.types[2] isa JuliaBUGS.OfArray{Float64,2}
        @test reconstructed.types[3] isa JuliaBUGS.OfVector
        @test reconstructed.types[4] isa JuliaBUGS.OfDict{Symbol}

        # Test tree_map_with_path
        paths_and_types = Tuple{Any,DataType}[]
        JuliaBUGS.tree_map_with_path(complex_type) do path, leaf
            push!(paths_and_types, (path, typeof(leaf)))
            return leaf
        end

        @test length(paths_and_types) == 4
        @test paths_and_types[1] == ((:a,), JuliaBUGS.OfReal)
        @test paths_and_types[2] == ((:b,), JuliaBUGS.OfArray{Float64,2})
        @test paths_and_types[3] == ((:c, :element), JuliaBUGS.OfArray{Any,2})
        @test paths_and_types[4] == ((:d, :value), JuliaBUGS.OfReal)
    end
end

@testset "Integration with @model macro" begin
    # Test with NamedTuple and of annotations
    JuliaBUGS.@model function test_model1((; x::of(Array, 3), y::of(Real, 0.0, 1.0)), n)
        for i in 1:n
            x[i] ~ Normal(0, 1)
        end
        return y ~ Uniform(0, 1)
    end

    # Test with regular parameters
    JuliaBUGS.@model function test_model2((; x, y), n)
        for i in 1:n
            x[i] ~ Normal(0, 1)
        end
        return y ~ Uniform(0, 1)
    end

    # Test model instantiation
    params = of((x=of(Array, 3), y=of(Real, 0.0, 1.0)))
    model1 = test_model1(rand(params), 3)
    @test model1 isa JuliaBUGS.BUGSModel

    model2 = test_model2((x=randn(3), y=0.5), 3)
    @test model2 isa JuliaBUGS.BUGSModel
end
