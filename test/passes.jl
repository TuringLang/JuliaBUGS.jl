using JuliaBUGS: analyze_program, CollectVariables
using JuliaBUGS: is_resolved
using JuliaBUGS: is_specified_by_data

@testset "CollectVariables Error Cases" begin
    # assign to data
    model_def = @bugs begin
        b = a
    end
    data = (b = [1, 2],)
    @test_throws ErrorException analyze_program(CollectVariables(model_def, data), model_def, data)

    model_def = @bugs begin
        x[1:3] = y[1:3]
    end
    data = (x = [1, missing, missing], y = [1, 2, 3])
    @test_throws ErrorException analyze_program(CollectVariables(model_def, data), model_def, data)

    # partially specified as data
    model_def = @bugs begin
        x[1:3] ~ dmnorm(y[1:3], E[:,:])
    end
    data = (x = [1, missing, missing], y = [1, 2, 3], E = [1 0 0; 0 1 0; 0 0 1])
    @test_throws ErrorException analyze_program(CollectVariables(model_def, data), model_def, data)

    # check access data array out-of-bound
    model_def = @bugs begin
        x[4] = 2
    end
    data = (x = [1, 2, 3],)
    @test_throws BoundsError analyze_program(CollectVariables(model_def, data), model_def, data)
end

@testset "is_specified_by_data" begin
    data = (a = [1, 2, 3], b = 2, c = [1, 2, missing], d = [missing, missing])
    @test is_specified_by_data(data, :b)
    @test_throws ErrorException is_specified_by_data(data, :c)
    @test !is_specified_by_data(data, :d, 1)
    @test !is_specified_by_data(data, :c, 3)
    @test !is_specified_by_data(data, :a, 1)
    @test is_specified_by_data(data, :c, 2:3)
    @test !is_specified_by_data(data, :d, 1:2)
    @test is_specified_by_data(data, :a, 1:2)
end

@testset "Constant propagation" begin
    model_def = @bugs begin
        a = b + 1
        c = d[1] + e[2]
        d[1] = a * 2
    end
    data = (b=1, e=[1, 2])

    scalars, array_sizes = analyze_program(CollectVariables(), model_def, data)
    has_new_val, transformed_variables = analyze_program(
        DataTransformation(scalars, array_sizes), model_def, data
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

@testset "Test compiler passes with $m" for m in [:leuk, :leukfr]
    model_def = JuliaBUGS.BUGSExamples.VOLUME_I[m].model_def
    data = JuliaBUGS.BUGSExamples.VOLUME_I[m].data
    inits = JuliaBUGS.BUGSExamples.VOLUME_I[m].inits[1]

    scalars, array_sizes = analyze_program(CollectVariables(), model_def, data)

    has_new_val, transformed_variables = analyze_program(
        DataTransformation(scalars, array_sizes), model_def, data
    )
    @test has_new_val == true
    @test all(!ismissing, transformed_variables[:Y])

    has_new_val, transformed_variables = analyze_program(
        DataTransformation(false, transformed_variables), model_def, data
    )

    @test has_new_val == true
    @test all(!ismissing, transformed_variables[:dN])

    array_bitmap, transformed_variables = analyze_program(
        PostChecking(data, transformed_variables), model_def, data
    )

    vars, array_sizes, array_bitmap, node_args, node_functions, dependencies = analyze_program(
        NodeFunctions(array_sizes, array_bitmap),
        model_def,
        merge_with_coalescence(data, transformed_variables),
    )

    compile(model_def, data, inits)
end
