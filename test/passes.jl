@testset "Test compiler passes with Luek" begin
    model_def = JuliaBUGS.BUGSExamples.leuk.model_def
    data = JuliaBUGS.BUGSExamples.leuk.data
    inits = JuliaBUGS.BUGSExamples.leuk.inits[1]

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

    vars, array_bitmap, transformed_variables = program!(
        PostChecking(data, transformed_variables), model_def, data
    )

    vars, array_sizes, array_bitmap, node_args, node_functions, dependencies = program!(
        NodeFunctions(vars, array_sizes, array_bitmap),
        model_def,
        merge_collections(data, transformed_variables),
    )

    compile(model_def, data, inits)
end
