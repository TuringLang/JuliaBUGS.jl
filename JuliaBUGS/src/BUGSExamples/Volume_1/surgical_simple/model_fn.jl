@model function surgical_simple((; p, r), N, n)
    for i in 1:N
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    end
end
