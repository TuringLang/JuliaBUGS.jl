name = "Bones"

model_def = @bugs begin
    for i in 1:nChild
        theta[i] ~ dnorm(0.0, 0.001)
        for j in 1:nInd
            for k in 1:(ncat[j] - 1)
                Q[i, j, k] = logistic(delta[j] * (theta[i] - gamma[j, k]))
            end
        end
        for j in 1:nInd
            p[i, j, 1] = 1 - Q[i, j, 1]
            for k in 2:(ncat[j] - 1)
                p[i, j, k] = Q[i, j, k - 1] - Q[i, j, k]
            end
            p[i, j, ncat[j]] = Q[i, j, ncat[j] - 1]
            grade[i, j] ~ dcat(p[i, j, 1:ncat[j]])
            var"cumulative.grade"[i, j] = cumulative(grade[i, j], grade[i, j])
        end
    end
end

data = (
    nChild = 13,
    nInd = 34,
    gamma = [0.7425 missing missing missing
             10.267 missing missing missing
             10.5215 missing missing missing
             9.3877 missing missing missing
             0.2593 missing missing missing
             -0.5998 missing missing missing
             10.5891 missing missing missing
             6.6701 missing missing missing
             8.8921 missing missing missing
             12.4275 missing missing missing
             12.4788 missing missing missing
             13.7778 missing missing missing
             5.8374 missing missing missing
             6.9485 missing missing missing
             13.7184 missing missing missing
             14.3476 missing missing missing
             4.8066 missing missing missing
             9.1037 missing missing missing
             10.7483 missing missing missing
             0.3887 1.0153 missing missing
             3.2573 7.0421 missing missing
             11.6273 14.4242 missing missing
             15.8842 17.4685 missing missing
             14.8926 16.7409 missing missing
             15.5487 16.872 missing missing
             15.4091 17.0061 missing missing
             3.9216 5.2099 missing missing
             15.475 16.9406 17.4944 missing
             0.4927 1.3556 2.3016 3.2535
             1.3059 1.8793 2.497 3.2306
             1.5012 1.8902 2.3689 2.9495
             0.8021 2.3873 3.9525 5.3198
             5.0022 6.3704 8.2832 10.4988
             4.0168 5.1537 7.1053 10.3038],
    delta = [2.9541 0.6603 0.7965 1.0495 5.7874 3.8376 0.6324 0.8272 0.6968 0.8747 0.8136 0.8246 0.6711 0.978 1.1528 1.6923 1.0331 0.5381 1.0688 8.1123 0.9974 1.2656 1.1802 1.368 1.5435 1.5006 1.6766 1.4297 3.385 3.3085 3.4007 2.0906 1.0954 1.5329],
    ncat = [2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 3 3 3 3 3 3 3 3 4 5 5 5 5 5 5],
    grade = [1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 1 1 1 1 1 1 1 1 2 1 1 2 1 1
             2 1 1 1 2 2 1 1 1 1 1 1 1 1 1 1 1 1 1 3 1 1 1 1 1 1 1 1 3 1 1 2 1 1
             2 1 1 1 2 2 1 1 1 1 1 1 1 1 1 1 1 1 1 3 1 1 1 1 1 1 1 1 4 3 3 3 1 1
             2 1 1 1 2 2 1 1 1 1 1 1 missing 1 1 1 1 1 1 3 1 1 1 1 1 1 1 1 4 5 4 3 1 1
             2 1 1 1 2 2 1 1 2 1 1 1 1 1 1 1 2 1 1 3 2 1 1 1 1 1 3 1 5 5 5 4 2 3
             2 1 1 1 2 2 1 2 1 1 1 1 1 2 1 1 2 missing 1 3 2 1 1 1 1 1 3 1 5 5 5 5 3 3
             2 1 1 1 2 2 1 1 1 missing missing 1 1 1 1 1 2 missing 1 3 3 1 1 1 1 1 3 1 5 5 5 5 3 3
             2 1 2 2 2 2 2 2 1 missing missing 1 2 2 1 1 2 2 1 3 2 1 1 1 1 1 3 1 5 5 5 5 3 4
             2 1 1 2 2 2 2 2 2 1 1 1 2 1 1 1 2 1 1 3 3 1 1 1 1 1 3 1 5 5 5 5 4 4
             2 1 2 2 2 2 2 2 2 1 1 1 2 2 2 1 2 missing 2 3 3 1 1 1 1 1 3 1 5 5 5 5 5 5
             2 1 missing 2 2 2 missing 2 2 1 missing missing 2 2 missing missing 2 1 2 3 3 missing 1 missing 1 1 3 1 5 5 5 5 5 5
             2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 3 3 3 1 missing 2 1 3 2 5 5 5 5 5 5
             2 2 2 2 2 2 2 2 2 2 missing 2 2 2 2 2 2 2 2 3 3 3 missing 2 missing 2 3 4 5 5 5 5 5 5]
)

inits = (
    theta = [0.5, 1, 2, 3, 5, 6, 7, 8, 9, 12, 13, 16, 18],
    grade = [missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing 1 1 missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing 1 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing 1 missing missing missing 1 missing missing missing 1 1 missing missing 1 1 missing missing missing missing missing 1 missing 1 missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing 1 missing 1 missing missing missing missing missing missing missing missing missing]
)
inits_alternative = (
    theta = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
    grade = [missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing 1 1 missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing 1 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing
             missing missing 1 missing missing missing 1 missing missing missing 1 1 missing missing 1 1 missing missing missing missing missing 1 missing 1 missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing
             missing missing missing missing missing missing missing missing missing missing 1 missing missing missing missing missing missing missing missing missing missing missing 1 missing 1 missing missing missing missing missing missing missing missing missing]
)

reference_results = nothing

bones = Example(name, model_def, data, inits, inits_alternative, reference_results)
