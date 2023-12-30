# Basic cases:

LHS = [
    :(x), # scalar
    :(x[1]), # tensor
    :(x[1, 2]), # 2d tensor

    :(x[b]), # tensor with index expression
    :(x[a[1]]),
    :(x[a[1], b[2]]),
    :(x[a[1] + 1]),
    :(x[1 + a[1]]),

    :(x[a[1]:b[2]]), # tensor with range expression

    :(x[a[1]:b[2], c[3]:d[4]]), # tensor with range expression
    :(x[f(a[1])]),
    :(x[f(a[1] + 1) + 1 : b[2]]) 
]

RHS = [
    1,
    :a,
    :(a + 1),

    x[y[1]],

    :(dnorm(0, 1e-4)),
    :(dnorm(0, 1)),
    :(dnorm(x[1], 1)),
    :(dnorm(x[1] + 1, 1)),
    :(dnorm(f(x[a[1]], 1), 1)),

    :(f(g(x[1]))),
    :(f(g(x[1] + 1))),
    :(f(g(x[a[1]]))),
    :(f(g(x[a[1] + 1] + h(y, 2, x[1])))),
]

FOR = [
    :(for i in 1:N
        x[i] ~ dnorm(0, 1)
    end),
    :(for i in 1:N
        Y[i] ~ dnorm(μ[i], τ)
        μ[i] = α + β * (x[i] - x̄)
    end)
]


@bugs(
    begin
        x ~ dnorm(0, 1)
        x[1] ~ dnorm(0, 1)
        x[1, 2] ~ dnorm(0, 1)

        x = 1
        x[1] = 1
        x[1, 2] = 1

        x[a[1]] ~ dnorm(0, 1)
        x[a[1], b[2]] ~ dnorm(0, 1)

        x[a[1] + 1] ~ dnorm(0, 1)
        x[1 + a[1]] ~ dnorm(0, 1)

        for i in 1:10
            x[i] ~ dnorm(0, 1)
        end
    end
) == MacroTools.@q begin
    x ~ dnorm(0, 1)
    x[1] ~ dnorm(0, 1)
    x[1, 2] ~ dnorm(0, 1)
    x = 1
    x[1] = 1
    x[1, 2] = 1
    x[a[1]] ~ dnorm(0, 1)
    x[a[1], b[2]] ~ dnorm(0, 1)
    x[a[1] + 1] ~ dnorm(0, 1)
    x[1 + a[1]] ~ dnorm(0, 1)
    for i in 1:10
        x[i] ~ dnorm(0, 1)
    end
end

# single line
(@bugs (x[1] = 1; y[1] ~ dnorm(0, 1))) == MacroTools.@q begin
    x[1] = 1
    y[1] ~ dnorm(0, 1)
end

# for loops
# loop bound is expression
(@bugs for i in 1:(N + 1)
    x[i] ~ dnorm(0, 1)
end) == MacroTools.@q for i in 1:(N + 1)
    x[i] ~ dnorm(0, 1)
end

# loop bound is tensor
(@bugs for i in 1:a[1]
    x[i] ~ dnorm(0, 1)
end) == MacroTools.@q for i in 1:a[1]
    x[i] ~ dnorm(0, 1)
end

# loop bound is tensor/scalar mixed expression
(@bugs for i in 1:(a[1] + b + 1)
    x[i] ~ dnorm(0, 1)
end) == MacroTools.@q for i in 1:(a[1] + b + 1)
    x[i] ~ dnorm(0, 1)
end

# Failure cases    
# loop variable is not scalar
(@bugs for 1 in 1:N
    x[i] ~ dnorm(0, 1)
end)

# nested indexing
@test_throws ErrorException JuliaBUGS.Parser.bugs_top(:(x[1] = y[1][1]), LineNumberNode(1))

