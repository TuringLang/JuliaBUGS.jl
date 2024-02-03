using JuliaBUGS: @bugs
using JuliaBUGS: JuliaBUGS, SemanticChecks
using JuliaBUGS.BUGSExamples: leuk
using JuliaBUGS.SemanticChecks: CompileState
using JuliaBUGS.SemanticChecks:
    determine_array_sizes!,
    concretize_colon_indexing!,
    compute_transformed!,
    check_multiple_assignments_pre_transform,
    check_multiple_assignments_post_transform!
using JuliaBUGS.SemanticChecks: build_eval_function
using MacroTools
using Test

##
@testset "determine_array_sizes!" begin
    model_def = leuk.model_def
    data = leuk.data

    state = SemanticChecks.CompileState(model_def, data)

    f = JuliaBUGS.SemanticChecks.build_eval_function(state, state.logical_for_statements[1])
    SemanticChecks.call(state.eval_module, f, 1, 1)

    determine_array_sizes!(state)
    array_sizes = state.array_sizes
    @test array_sizes[Symbol("dL0.star")] == [17]
    @test array_sizes[:dN] == [42, 17]
    @test array_sizes[Symbol("obs.t")] == (42,)
    @test array_sizes[Symbol("S.treat")] == [17]
    @test array_sizes[Symbol("S.placebo")] == [17]
    @test array_sizes[:dL0] == [17]
    @test array_sizes[:Idt] == [42, 17]
    @test array_sizes[:Z] == (42,)
    @test array_sizes[:fail] == (42,)
    @test array_sizes[:mu] == [17]
    @test array_sizes[:Y] == [42, 17]
    @test array_sizes[:t] == (18,)
end

@testset "concretize_colon_indexing!" begin
    test_expr = JuliaBUGS.@bugs begin
        for i in 1:3
            x[i] = sum(Y[:])
        end
        z ~ dist(x[:], Y[:])
    end
    state = SemanticChecks.CompileState(test_expr, (; Y=[1, 2, 3],))
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    @test state.logical_for_statements[1].rhs == :(sum(Y[1:3]))
    @test state.stochastic_statements[1].rhs == :(dist(x[1:3], Y[1:3]))
end

@testset "check_multiple_assignments" begin
    @test 1
    model_def = @bugs begin
        for i in 1:3
            x[i] = y[i]
        end

        for i in 1:10
            x[i] ~ Normal(0, 1)
        end

        z = sum(x[:])
    end

    state = CompileState(model_def, (y=[1, 2, 3],))
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    @test state.logical_statements[1].rhs == :(sum(x[1:10]))
    check_multiple_assignments_pre_transform(state)
    @test state.logical_definition_bitmap[:x] == Bool[1, 1, 1, 0, 0, 0, 0, 0, 0, 0]
    @test state.stochastic_definition_bitmap[:x] == Bool[1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    compute_transformed!(state)
    check_multiple_assignments_post_transform!(state)

    state = CompileState(model_def, (;))
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    check_multiple_assignments_pre_transform(state)
    compute_transformed!(state)
    @test_throws ErrorException check_multiple_assignments_post_transform!(state)

    # test 2
    model_def = @bugs begin
        x[1:3] = y[1:3]
        x[1] = 2
    end

    state = CompileState(model_def, (y=[1, 2, 3],))
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    @test_throws ErrorException check_multiple_assignments_pre_transform(state)
end

@testset "compute_transformed!" begin
    @testset "with Leuk" begin
        model_def = leuk.model_def
        data = leuk.data

        state = SemanticChecks.CompileState(model_def, data)
        determine_array_sizes!(state)
        concretize_colon_indexing!(state)
        compute_transformed!(state)

        # TODO: use older version of `JuliaBUGS.program!` to test this, remove in the future
        scalars, array_sizes = JuliaBUGS.program!(
            JuliaBUGS.CollectVariables(), model_def, data
        )
        has_new_val, transformed = JuliaBUGS.program!(
            JuliaBUGS.ConstantPropagation(scalars, array_sizes), model_def, data
        )
        while has_new_val
            has_new_val, transformed = JuliaBUGS.program!(
                JuliaBUGS.ConstantPropagation(false, transformed), model_def, data
            )
        end
        array_bitmap, transformed = JuliaBUGS.program!(
            JuliaBUGS.PostChecking(data, transformed), model_def, data
        )

        D = SemanticChecks.get_data_and_transformed_variables(state)
        @test D[Symbol("dL0.star")] == transformed[Symbol("dL0.star")]
        @test D[:dN] == transformed[:dN]
        @test D[:mu] == transformed[:mu]
        @test D[:Y] == transformed[:Y]
        @test D[:c] == transformed[:c]
        @test D[:r] == transformed[:r]
    end

    @testset "artificial example" begin
        model_def = @bugs begin
            x[1:3] = y[1:3]
            x[5] = x[4]
            z[1:2] = x[5:6]
        end
        state = CompileState(
            model_def, (y=[1, 2, 3], x=[missing, missing, missing, 1, missing, 2])
        )
        determine_array_sizes!(state)
        concretize_colon_indexing!(state)
        compute_transformed!(state)
        D = SemanticChecks.get_data_and_transformed_variables(state)
        @test D[:x] == [1, 2, 3, 1, 1, 2]
    end
end
