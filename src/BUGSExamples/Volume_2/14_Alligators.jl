alligators = (
    model_def=(@bugs begin
        # PRIORS
        alpha[1] = 0 # zero contrast for baseline food
        for k in 2:K
            alpha[k] ~ dnorm(0, 0.00001) # vague priors
        end
        # Loop around lakes:
        for k in 1:K
            beta[1, k] = 0
        end # corner-point contrast with first lake
        for i in 2:I
            beta[i, 1] = 0 # zero contrast for baseline food
            for k in 2:K
                beta[i, k] ~ dnorm(0, 0.00001) # vague priors
            end
        end
        # Loop around sizes:
        for k in 1:K
            gamma[1, k] = 0 # corner-point contrast with first size
        end
        for j in 2:J
            gamma[j, 1] = 0 # zero contrast for baseline food
            for k in 2:K
                gamma[j, k] ~ dnorm(0, 0.00001) # vague priors
            end
        end

        # LIKELIHOOD   
        for i in 1:I  # loop around lakes
            for j in 1:J  # loop around sizes

                # Multinomial response
                # X[i, j, 1:K] ~ dmulti(p[i, j, 1:K], n[i, j])
                # n[i, j] = sum(X[i, j])
                # for k in 1:K  # loop around foods
                #     p[i, j, k] = phi[i, j, k] / sum(phi[i, j])
                #     log(phi[i, j, k]) < -alpha[k] + beta[i, k] + gamma[j, k]
                # end

                # Fit standard Poisson regressions relative to baseline
                lambda[i, j] ~ dflat()   # vague priors
                for k in 1:K  # loop around foods
                    X[i, j, k] ~ dpois(mu[i, j, k])
                    mu[i, j, k] = expr(lambda[i, j] + alpha[k] + beta[i, k] + gamma[j, k])
                end
            end
        end

        # TRANSFORM OUTPUT TO ENABLE COMPARISON
        # WITH AGRESTI'S RESULTS
        for k in 1:K  # loop around foods
            for i in 1:I  # loop around lakes
                b[i, k] = beta[i, k] - mean(beta[:, k]) # sum to zero constraint
            end
            for j in 1:J  # loop around sizes
                g[j, k] = gamma[j, k] - mean(gamma[:, k]) # sum to zero constraint
            end
        end
    end),
    data=(
        I=4,
        J=2,
        K=5,
        X=rreshape(
            [
                23,
                4,
                2,
                2,
                8,
                7,
                0,
                1,
                3,
                5,
                5,
                11,
                1,
                0,
                3,
                13,
                8,
                6,
                1,
                0,
                5,
                11,
                2,
                1,
                5,
                8,
                7,
                6,
                3,
                5,
                16,
                19,
                1,
                2,
                3,
                17,
                1,
                0,
                1,
                3,
            ],
            (4, 2, 5),
        ),
    ),
    inits=[
        (
            alpha=[missing, 0, 0, 0, 0],
            beta=rreshape(
                [
                    missing,
                    missing,
                    missing,
                    missing,
                    missing,
                    missing,
                    0,
                    0,
                    0,
                    0,
                    missing,
                    0,
                    0,
                    0,
                    0,
                    missing,
                    0,
                    0,
                    0,
                    0,
                ],
                (4, 5),
            ),
            gamma=rreshape(
                [missing, missing, missing, missing, missing, missing, 0, 0, 0, 0], (2, 5)
            ),
            lambda=rreshape([0, 0, 0, 0, 0, 0, 0, 0], (4, 2)),
        ),
        (
            alpha=[missing, 1, 1, 1, 1],
            beta=rreshape(
                [
                    missing,
                    missing,
                    missing,
                    missing,
                    missing,
                    missing,
                    2,
                    2,
                    2,
                    2,
                    missing,
                    2,
                    2,
                    2,
                    2,
                    missing,
                    2,
                    2,
                    2,
                    2,
                ],
                (4, 5),
            ),
            gamma=rreshape(
                [missing, missing, missing, missing, missing, missing, 3, 3, 3, 3], (2, 5)
            ),
            lambda=rreshape([4, 4, 4, 4, 4, 4, 4, 4], (4, 2)),
        ),
    ],
)
