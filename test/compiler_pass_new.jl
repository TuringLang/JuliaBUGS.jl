##
using JuliaBUGS: program!, CollectVariables, ConstantPropagation, PostChecking

##
m = :leuk
model_def = JuliaBUGS.BUGSExamples.leuk.model_def
data = JuliaBUGS.BUGSExamples.leuk.data
inits = JuliaBUGS.BUGSExamples.leuk.inits[1]

##
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
state = CompileState(model_def, data, inits)
determine_array_sizes!(state)
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