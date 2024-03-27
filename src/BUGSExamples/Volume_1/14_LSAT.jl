name = "LSAT: item response"

model_def = @bugs begin
    # Calculate individual (binary) responses to each test from multinomial data
    for j in 1:culm[1]
        for k in 1:T
            r[j, k] = response[1, k]
        end
    end

    for i in 2:R
        for j in (culm[i - 1] + 1):culm[i]
            for k in 1:T
                r[j, k] = response[i, k]
            end
        end
    end

    # Rasch model
    for j in 1:N
        for k in 1:T
            logit(p[j, k]) = beta * theta[j] - alpha[k]
            r[j, k] ~ dbern(p[j, k])
        end
        theta[j] ~ dnorm(0, 1)
    end

    # Priors
    for k in 1:T
        alpha[k] ~ dnorm(0, 0.0001)
        a[k] = alpha[k] - mean(alpha[:])
    end
    beta ~ truncated(dflat(), 0, nothing)
end

data = (
    N = 1000,
    R = 32,
    T = 5,
    culm = [3, 9, 11, 22, 23, 24, 27, 31, 32, 40, 40, 56, 56, 59, 61, 76, 86, 115,
        129, 210, 213, 241, 256, 336, 352, 408, 429, 602, 613, 674, 702, 1000],
    response = [0 0 0 0 0
                0 0 0 0 1
                0 0 0 1 0
                0 0 0 1 1
                0 0 1 0 0
                0 0 1 0 1
                0 0 1 1 0
                0 0 1 1 1
                0 1 0 0 0
                0 1 0 0 1
                0 1 0 1 0
                0 1 0 1 1
                0 1 1 0 0
                0 1 1 0 1
                0 1 1 1 0
                0 1 1 1 1
                1 0 0 0 0
                1 0 0 0 1
                1 0 0 1 0
                1 0 0 1 1
                1 0 1 0 0
                1 0 1 0 1
                1 0 1 1 0
                1 0 1 1 1
                1 1 0 0 0
                1 1 0 0 1
                1 1 0 1 0
                1 1 0 1 1
                1 1 1 0 0
                1 1 1 0 1
                1 1 1 1 0
                1 1 1 1 1]
)

inits = (alpha = [0, 0, 0, 0, 0], beta = 1)
inits_alternative = (alpha = [1.0, 1.0, 1.0, 1.0, 1.0], beta = 2)

reference_results = nothing

lsat = Example(name, model_def, data, inits, inits_alternative, reference_results)
