using JuliaBUGS: JuliaBUGS, Backend
using JuliaBUGS.BUGSExamples: leuk
using JuliaBUGS.Backend: determine_array_sizes!, concretize_colon_indexing!
using MacroTools
using Test

##
model_def = leuk.model_def
data = leuk.data

state = Backend.CompileState(model_def, data)

determine_array_sizes!(state)
@testset "determine_array_sizes!" begin
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
    state = Backend.CompileState(test_expr, (;Y=[1, 2, 3],))
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    @test state.logical_for_statements[1].rhs == :(sum(Y[1:3]))
    @test state.stochastic_statements[1].rhs == :(dist(x[1:3], Y[1:3]))
end

compute_transformed!(state)

##

model_def = @bugs begin
    x[1:3] = y[1:3]
    x[5] = x[4]
    z[1:2] = x[5:6]
end

state = CompileState(
    model_def, (y=[1, 2, 3], x=[missing, missing, missing, 1, missing, 2]), NamedTuple()
)

determine_array_sizes!(state)
compute_transformed!(state)

@assert state.merged_data_and_transformed[:x] == [1, 2, 3, 1, 1, 2]

model_def = @bugs begin
    for i in 1:3
        x[i] = y[i]
    end

    for i in 1:10
        x[i] ~ Normal(0, 1)
    end

    z = sum(x[:])
end

state = CompileState(model_def, (y=[1, 2, 3],), NamedTuple())
state = CompileState(model_def, (;), NamedTuple())

model_def = @bugs begin
    x[1:3] = y[1:3]
    x[1] = 2
end

model_def = @bugs begin
    for i in 2:3
        x[(i - 1):(i + 1)] = y[1:3]
    end
end

state = CompileState(model_def, (y=[1, 2, 3],), NamedTuple())

determine_array_sizes!(state)
check_multiple_assignments(state)

##
using JuliaBUGS: program!, CollectVariables, ConstantPropagation, PostChecking

scalars, array_sizes = program!(CollectVariables(), model_def, data)
has_new_val, transformed = program!(
    ConstantPropagation(scalars, array_sizes), model_def, data
)
while has_new_val
    has_new_val, transformed = program!(
        ConstantPropagation(false, transformed), model_def, data
    )
end
array_bitmap, transformed = program!(PostChecking(data, transformed), model_def, data)

##