using JuliaBUGS: @bugs
using JuliaBUGS: JuliaBUGS, SemanticAnalysis
using JuliaBUGS.BUGSExamples: leuk
using JuliaBUGS.SemanticAnalysis: CompileState
using JuliaBUGS.SemanticAnalysis:
    determine_array_sizes!,
    concretize_colon_indexing!,
    compute_transformed!,
    check_multiple_assignments_pre_transform,
    check_multiple_assignments_post_transform!
using JuliaBUGS.SemanticAnalysis: build_eval_function
using MacroTools
using Test

##
@testset "determine_array_sizes!" begin
    model_def = leuk.model_def
    data = leuk.data
    state = SemanticAnalysis.CompileState(model_def, data)

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
    state = SemanticAnalysis.CompileState(test_expr, (; Y=[1, 2, 3],))
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    @test state.logical_for_statements[1].rhs == :(sum(Y[1:3]))
    @test state.stochastic_statements[1].rhs == :(dist(x[1:3], Y[1:3]))
end

@testset "check_multiple_assignments" begin
    # test 1
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

        state = SemanticAnalysis.CompileState(model_def, data)
        determine_array_sizes!(state)
        concretize_colon_indexing!(state)
        compute_transformed!(state)

        # hand prepared transformed variables
        var"L0.star" = Vector{Float64}(undef, 17)
        dN = Array{Float64}(undef, 42, 17)
        mu = Vector{Float64}(undef, 17)
        Y = Array{Float64}(undef, 42, 17)
        c = Array{Float64}(undef, 42)
        r = Array{Float64}(undef, 42)
        for i in 1:17
            var"L0.star"[i] = 0.1 * (data.t[i + 1] - data.t[i])
            mu[i] = var"L0.star"[i] * 0.001
        end
        for i in 1:42, j in 1:17
            Y[i, j] = JuliaBUGS.BUGSPrimitives._step(data.var"obs.t"[i] - data.t[j] + data.eps)
            dN[i, j] = Y[i,j] * JuliaBUGS.BUGSPrimitives._step(data.t[j+1] - data.var"obs.t"[i] - data.eps) * data.fail[i]
        end

        D = SemanticAnalysis.get_data_and_transformed_variables(state)
        @test D[Symbol("dL0.star")] == var"L0.star"
        @test D[:dN] == dN
        @test D[:mu] == mu
        @test D[:Y] == Y
        @test D[:c] == 0.001
        @test D[:r] == 0.1
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
        D = SemanticAnalysis.get_data_and_transformed_variables(state)
        @test D[:x] == [1, 2, 3, 1, 1, 2]
    end
end

##
model_def = leuk.model_def
data = leuk.data
state = SemanticAnalysis.CompileState(model_def, data)
st = state.logical_for_statements[1]

using JuliaBUGS.SemanticAnalysis: range_covered, is_special, unpack_expr, determine_array_sizes_easy!, ForStatement

range_covered(st)

unpack_expr(st.lhs, st.loop_vars)

expr = MacroTools.@q for i in 1:10
    for j in 1:3
        y[i+1, j-1] = 2
    end
end

st = ForStatement(expr, data)

range_covered(st)
