using JuliaBUGS:
    CollectVariables,
    # DependencyGraph,
    # NodeFunctions,
    ArrayElement,
    ArrayVar,
    program!,
    compile

##
model_def = @bugsast begin
    for i in 1:N
        x[i] = d[i] * 2
        x[i] ~ dnorm(0, 1)
    end
end

data = (
    N = 10,
    d = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
) |> Dict ∘ pairs

##

vars, array_sizes, transformed_variables, array_bitmap = program!(CollectVariables(), model_def, data);