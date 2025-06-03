using JuliaBUGS
using JuliaBUGS: @parameters, @model

@testset "Model Macro (@model and @parameters)" begin
    @parameters struct Tp
        r
        b
        alpha0
        alpha1
        alpha2
        alpha12
        tau
    end

    #! format: off
    @model function seeds(
        (; r, b, alpha0, alpha1, alpha2, alpha12, tau)::Tp, x1, x2, N, n
    )
        for i in 1:N
            r[i] ~ dbin(p[i], n[i])
            b[i] ~ dnorm(0.0, tau)
            p[i] = logistic(
                alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
            )
        end
        alpha0 ~ dnorm(0.0, 1.0E-6)
        alpha1 ~ dnorm(0.0, 1.0E-6)
        alpha2 ~ dnorm(0.0, 1.0E-6)
        alpha12 ~ dnorm(0.0, 1.0E-6)
        tau ~ dgamma(0.001, 0.001)
        sigma = 1 / sqrt(tau)
    end
    #! format: on

    # Try destructuring the random variables but forgetting to include one (tau).
    @test_throws ErrorException begin
        #! format: off
        @model function seeds(
            #                                       tau is missing
            (; r, b, alpha0, alpha1, alpha2, alpha12)::Tp, x1, x2, N, n
        )
            for i in 1:N
                r[i] ~ dbin(p[i], n[i])
                b[i] ~ dnorm(0.0, tau)
                p[i] = logistic(
                    alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
                )
            end
            alpha0 ~ dnorm(0.0, 1.0E-6)
            alpha1 ~ dnorm(0.0, 1.0E-6)
            alpha2 ~ dnorm(0.0, 1.0E-6)
            alpha12 ~ dnorm(0.0, 1.0E-6)
            tau ~ dgamma(0.001, 0.001)
            sigma = 1 / sqrt(tau)
        end
        #! format: on
    end

    # Try leaving out one constant variable.
    @test_throws ErrorException begin
        #! format: off
        @model function seeds(
            #                                                  x1 is missing
            (; r, b, alpha0, alpha1, alpha2, alpha12, tau)::Tp, x2, N, n
        )
            for i in 1:N
                r[i] ~ dbin(p[i], n[i])
                b[i] ~ dnorm(0.0, tau)
                p[i] = logistic(
                    alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
                )
            end
            alpha0 ~ dnorm(0.0, 1.0E-6)
            alpha1 ~ dnorm(0.0, 1.0E-6)
            alpha2 ~ dnorm(0.0, 1.0E-6)
            alpha12 ~ dnorm(0.0, 1.0E-6)
            tau ~ dgamma(0.001, 0.001)
            sigma = 1 / sqrt(tau)
        end
        #! format: on
    end

    data = JuliaBUGS.BUGSExamples.seeds.data
    m = seeds(Tp(), data.x1, data.x2, data.N, data.n)

    # use NamedTuple to pass parameters
    # with missing values
    N = data.N
    params_nt = (
        r=fill(missing, N),
        b=fill(missing, N),
        alpha0=missing,
        alpha1=missing,
        alpha2=missing,
        alpha12=missing,
        tau=missing,
    )
    m = seeds(params_nt, data.x1, data.x2, data.N, data.n)

    params_nt_with_data = (
        r=data.r,
        b=JuliaBUGS.ParameterPlaceholder(),
        alpha0=JuliaBUGS.ParameterPlaceholder(),
        alpha1=JuliaBUGS.ParameterPlaceholder(),
        alpha2=JuliaBUGS.ParameterPlaceholder(),
        alpha12=JuliaBUGS.ParameterPlaceholder(),
        tau=JuliaBUGS.ParameterPlaceholder(),
    )
    m = seeds(params_nt_with_data, data.x1, data.x2, data.N, data.n)
end
