using JuliaBUGS: analyze_program, CollectVariables, DataTransformation
using JuliaBUGS: is_resolved
using JuliaBUGS: is_specified_by_data, is_partially_specified_as_data

@testset "CollectVariables Error Cases" begin
    # assign to data
    model_def = @bugs begin
        b = a
    end
    data = (b=[1, 2],)
    @test_throws ErrorException analyze_program(
        CollectVariables(model_def, data), model_def, data
    )

    model_def = @bugs begin
        x[1:3] = y[1:3]
    end
    data = (x=[1, missing, missing], y=[1, 2, 3])
    @test_throws ErrorException analyze_program(
        CollectVariables(model_def, data), model_def, data
    )

    # partially specified as data
    model_def = @bugs begin
        x[1:3] ~ dmnorm(y[1:3], E[:, :])
    end
    data = (x=[1, missing, missing], y=[1, 2, 3], E=[1 0 0; 0 1 0; 0 0 1])
    @test_throws ErrorException analyze_program(
        CollectVariables(model_def, data), model_def, data
    )

    # check access data array out-of-bound
    model_def = @bugs begin
        x[4] = 2
    end
    data = (x=[1, 2, 3],)
    @test_throws BoundsError analyze_program(
        CollectVariables(model_def, data), model_def, data
    )
end

@testset "is_specified_by_data" begin
    data = (a=2, b=[1, 2, 3], c=[1, 2, missing], d=[missing, missing, missing])

    # a is data
    @test is_specified_by_data(data, :a)
    # c is Array, but no indices
    @test_throws ErrorException is_specified_by_data(data, :c)
    # index doesn't contain UnitRange
    @test is_specified_by_data(data, :b, 1)
    @test !is_specified_by_data(data, :d, 1)
    @test is_specified_by_data(data, :c, 1)
    @test !is_specified_by_data(data, :c, 3)
    # index contains UnitRange
    @test is_specified_by_data(data, :b, 1:2)
    @test is_specified_by_data(data, :c, 1:2)
    @test is_specified_by_data(data, :c, 2:3)
    @test !is_specified_by_data(data, :d, 1:2)

    @test !is_partially_specified_as_data(data, :c, 1:2)
    @test is_partially_specified_as_data(data, :c, 2:3)
    @test !is_partially_specified_as_data(data, :b, 1:2)
    @test !is_partially_specified_as_data(data, :d, 1:2)
end

@testset "Constant propagation" begin
    model_def = @bugs begin
        a = b + 1
        c = d[1] + e[2]
        d[1] = a * 2
    end
    data = (b=1, e=[1, 2])

    scalars, array_sizes = analyze_program(
        CollectVariables(model_def, data), model_def, data
    )

    transformed_variables = Dict{Symbol,Any}(
        :a => missing, :c => missing, :d => Union{Int,Missing}[missing,]
    )

    has_new_val, transformed_variables = analyze_program(
        DataTransformation(false, transformed_variables), model_def, data
    )
    @test has_new_val == true
    @test transformed_variables[:a] == 2

    has_new_val, transformed_variables = analyze_program(
        DataTransformation(false, transformed_variables), model_def, data
    )
    @test has_new_val == true
    @test transformed_variables[:c] == 6

    has_new_val, transformed_variables = analyze_program(
        DataTransformation(false, transformed_variables), model_def, data
    )
    @test has_new_val == false
end
