# test variables exist on the left hand side of the both kinds of assignment
@test_throws ErrorException compile((@bugs begin
    a ~ Normal(0, 1)
    b = a
    b ~ Normal(0, 1)
end), (;), (;))

@test_throws ErrorException compile((@bugs begin
    a ~ Normal(0, 1)
    b ~ Normal(0, 1)
    b = a
end), (;), (;))

compile((@bugs begin
    a ~ Normal(0, 1)
    b ~ Normal(0, 1)
    b = a
end), (; a=1), (;))

# assign array variable to another array variable
model = compile((@bugs begin
    b[1:2] ~ dmnorm(μ[:], σ[:, :])
    a[1:2] = b[:]
end), (; μ=[0, 1], σ=[1 0; 0 1]), (;))
