using JuliaBUGS: CollectVariables, DataTransformation, CheckRepeatedAssignments
using JuliaBUGS: is_resolved
using JuliaBUGS: is_specified_by_data, is_partially_specified_as_data

@testset "CollectVariables Error Cases" begin
    # assign to data
    model_def = @bugs begin
        b = a
    end
    data = (b=[1, 2],)
    @test_throws ErrorException JuliaBUGS.determine_array_sizes(model_def, data)

    model_def = @bugs begin
        x[1:3] = y[1:3]
    end
    data = (x=[1, missing, missing], y=[1, 2, 3])
    @test_throws ErrorException JuliaBUGS.determine_array_sizes(model_def, data)

    # partially specified as data
    model_def = @bugs begin
        x[1:3] ~ dmnorm(y[1:3], E[:, :])
    end
    data = (x=[1, missing, missing], y=[1, 2, 3], E=[1 0 0; 0 1 0; 0 0 1])
    @test_throws ErrorException JuliaBUGS.determine_array_sizes(model_def, data)

    # check access data array out-of-bound
    model_def = @bugs begin
        x[4] = 2
    end
    data = (x=[1, 2, 3],)
    @test_throws BoundsError JuliaBUGS.determine_array_sizes(model_def, data)
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

    non_data_scalars, non_data_array_sizes = JuliaBUGS.determine_array_sizes(
        model_def, data
    )

    eval_env = JuliaBUGS.create_eval_env(non_data_scalars, non_data_array_sizes, data)

    pass = DataTransformation(eval_env, false, Ref(false))
    JuliaBUGS.analyze_block(pass, model_def)
    (; new_value_added, env) = pass
    @test new_value_added == true
    @test env[:a] == 2

    pass = DataTransformation(env, false, Ref(true))
    JuliaBUGS.analyze_block(pass, model_def)
    (; new_value_added, env) = pass
    @test new_value_added == true
    @test env[:c] == 6

    pass = DataTransformation(env, false, Ref(true))
    JuliaBUGS.analyze_block(pass, model_def)
    (; new_value_added, env) = pass
    @test new_value_added == false
end

@testset "CheckRepeatedAssignments" begin
    @testset "with Leuk" begin
        model_def = JuliaBUGS.BUGSExamples.leuk.model_def
        data = JuliaBUGS.BUGSExamples.leuk.data
        inits = JuliaBUGS.BUGSExamples.leuk.inits

        scalars, array_sizes = JuliaBUGS.determine_array_sizes(model_def, data)

        pass = JuliaBUGS.CheckRepeatedAssignments(model_def, data, array_sizes)
        JuliaBUGS.analyze_block(pass, model_def)
        repeat_scalars, suspect_arrays = JuliaBUGS.post_process(pass)

        @test isempty(repeat_scalars)
        @test collect(keys(suspect_arrays)) == [:dN]
    end

    @testset "error cases" begin
        data = (;)

        @testset "repeated scalar logical assignment" begin
            model_def = @bugs begin
                a = 1
                a = 2
            end
            @test_throws ErrorException JuliaBUGS.determine_array_sizes(model_def, data)
        end

        @testset "repeated scalar stochastic assignment" begin
            model_def = @bugs begin
                a ~ Normal(0, 1)
                a ~ Normal(0, 2)
            end
            @test_throws ErrorException JuliaBUGS.determine_array_sizes(model_def, data)
        end

        @testset "repeated array element assignment" begin
            model_def = @bugs begin
                x[1] = 1
                x[1] = 2
            end
            scalars, array_sizes = JuliaBUGS.determine_array_sizes(model_def, data)
            @test_throws ErrorException JuliaBUGS.check_repeated_assignments(
                model_def, data, array_sizes
            )
        end

        @testset "repeated array assignment with range" begin
            model_def = @bugs begin
                x[1] = 1
                for i in 1:2
                    x[i:(i + 1)] = i
                end
            end
            scalars, array_sizes = JuliaBUGS.determine_array_sizes(model_def, data)
            @test_throws ErrorException JuliaBUGS.check_repeated_assignments(
                model_def, data, array_sizes
            )
        end

        @testset "repeated array assignment with range" begin
            model_def = @bugs begin
                x[1] ~ Normal(0, 1)
                x[1:2] ~ MvNormal(a[:], b[:, :])
            end
            data = (a=[1, 2], b=[1 0; 0 1])
            scalars, array_sizes = JuliaBUGS.determine_array_sizes(model_def, data)
            @test_throws ErrorException JuliaBUGS.check_repeated_assignments(
                model_def, data, array_sizes
            )
        end
    end
end

@testset "lower bound greater than upper bound" begin
    model_def = @bugs begin
        for i in 2:1
            a[i] ~ dnorm(0, 1)
        end
    end
    data = (;)
    @test_warn "In BUGS, if the lower bound of for loop is greater than the upper bound, the loop will be skipped." compile(
        model_def, data, (;)
    )
    model = compile(model_def, data, (;))
    @test length(model.graph_evaluation_data.sorted_parameters) == 0
end
