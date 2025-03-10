name = "Eye Tracking: dirichlet process prior"

model_def = @bugs begin
    for i in 1:N
        S[i] ~ dcat(var"pi"[:])
        mu[i] = theta[S[i]]
        x[i] ~ dpois(mu[i])
        for j in 1:C
            SC[i, j] = equals(j, S[i])
        end
    end

    # Precision Parameter
    alpha = 1
    # alpha ~ dgamma(0.1, 0.1)

    # Constructive DPP
    p[1] = r[1]
    for j in 2:C
        p[j] = r[j] * (1 - r[j - 1]) * p[j - 1] / r[j - 1]
    end
    p_sum = sum(p[:])
    for j in 1:C
        theta[j] ~ dgamma(A, B)
        r[j] ~ dbeta(1, alpha)
        # scaling to ensure sum to 1
        var"pi"[j] = p[j] / p_sum
    end
    # hierarchical prior on theta[i] or preset parameters
    A ~ dexp(0.1)
    B ~ dgamma(0.1, 0.1)
    # A = 1
    # B = 1

    # total clusters
    K = sum(cl[:])
    for j in 1:C
        sumSC[j] = sum(SC[:, j])
        cl[j] = step(sumSC[j] - 1)
    end
end

original = """
model{   
    for( i in 1 : N ) {
        S[i] ~ dcat(pi[])
        mu[i] <- theta[S[i]]
        x[i] ~ dpois(mu[i])
        for (j in 1 : C) {
            SC[i, j] <- equals(j, S[i])
        }
    }

    # Precision Parameter
    alpha <- 1
    # alpha~ dgamma(0.1,0.1)
    
    # Constructive DPP
    p[1] <- r[1]
    for (j in 2 : C) {
        p[j] <- r[j] * (1 - r[j - 1]) * p[j -1 ] / r[j - 1]
    }
    p.sum <- sum(p[])
    for (j in 1:C){
        theta[j] ~ dgamma(A, B)
        r[j] ~ dbeta(1, alpha)
        # scaling to ensure sum to 1
        pi[j] <- p[j] / p.sum
    }
    
    # hierarchical prior on theta[i] or preset parameters
    A ~ dexp(0.1)
    B ~ dgamma(0.1, 0.1)
    # A <- 1
    # B <- 1
    
    # total clusters
    K <- sum(cl[])
    for (j in 1 : C) {
        sumSC[j] <- sum(SC[ , j])
        cl[j] <- step(sumSC[j] -1)
    }
}
"""

data = (
    x = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2,
        2, 3, 3, 3, 3, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 8, 9, 9, 10, 10,
        11, 11, 12, 12, 14, 15, 15, 17, 17, 22, 24, 34],
    N = 101,
    C = 10
)

inits = NamedTuple()

inits_alternative = NamedTuple()

# fixed A and B, fixed alpha = 1, C = 10 (max categories)
reference_results = (
    K = (mean = 6.918, std = 1.491),
    var"mu[92]" = (mean = 13.37, std = 2.949)
)
# prior and data conflict.

# variable A and B, fixed alpha = 1, C = 10 (max categories)
reference_results_variable = (
    A = (mean = 0.6891, std = 0.4272),
    B = (mean = 0.0863, std = 0.06417),
    K = (mean = 7.351, std = 1.394),
    var"mu[92]" = (mean = 11.1, std = 2.983)
)

eye_tracking = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)