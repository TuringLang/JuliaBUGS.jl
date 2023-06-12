linear_regression = (
    model_def = @bugsast begin
        for i in 1:N
            Y[i] ~ dnorm(μ[i], τ)
            μ[i] = α + β * (x[i] - xbar)
        end
        τ ~ dgamma(0.001, 0.001)
        σ = 1 / sqrt(τ)
        logτ = log(τ)
        α ~ dnorm(0.0, 1e-6)
        β ~ dnorm(0.0, 1e-6)
    end,
    data = Dict(:x => [1, 2, 3, 4, 5], :Y => [1, 3, 3, 3, 5], :xbar => 3, :N => 5), 
    inits = [NamedTuple(), NamedTuple()]
)