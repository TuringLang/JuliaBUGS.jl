@testset "Constant propagation" begin
    model_def = @bugs begin
        a = b + 1
        c = d[1] + e[2]
        d[1] = a * 2
    end
    data = (b=1, e=[1, 2])

    scalars, array_sizes = program!(CollectVariables(), model_def, data)
    has_new_val, transformed_variables = program!(
        ConstantPropagation(scalars, array_sizes), model_def, data
    )
    @test has_new_val == true
    @test transformed_variables[:a] == 2

    has_new_val, transformed_variables = program!(
        ConstantPropagation(false, transformed_variables), model_def, data
    )
    @test has_new_val == true
    @test transformed_variables[:c] == 6

    has_new_val, transformed_variables = program!(
        ConstantPropagation(false, transformed_variables), model_def, data
    )
    @test has_new_val == false
end

@testset "Test compiler passes with $m" for m in [:leuk, :leukfr]
    model_def = JuliaBUGS.BUGSExamples.VOLUME_I[m].model_def
    data = JuliaBUGS.BUGSExamples.VOLUME_I[m].data
    inits = JuliaBUGS.BUGSExamples.VOLUME_I[m].inits[1]

    scalars, array_sizes = program!(CollectVariables(), model_def, data)

    has_new_val, transformed_variables = program!(
        ConstantPropagation(scalars, array_sizes), model_def, data
    )
    @test has_new_val == true
    @test all(!ismissing, transformed_variables[:Y])

    has_new_val, transformed_variables = program!(
        ConstantPropagation(false, transformed_variables), model_def, data
    )

    @test has_new_val == true
    @test all(!ismissing, transformed_variables[:dN])

    array_bitmap, transformed_variables = program!(
        PostChecking(data, transformed_variables), model_def, data
    )

    vars, array_sizes, array_bitmap, node_args, node_functions, dependencies = program!(
        NodeFunctions(array_sizes, array_bitmap),
        model_def,
        merge_collections(data, transformed_variables),
    )

    compile(model_def, data, inits)
end
