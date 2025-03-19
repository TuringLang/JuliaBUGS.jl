# TODO: make this available in JuliaBUGS
function _logjoint(model::JuliaBUGS.BUGSModel)
    return JuliaBUGS.evaluate!!(model)[2]
end

@testset "Log density" begin
    @testset "Log density of distributions" begin
        @testset "dbin (Binomial)" begin
            dist = dbin(0.1, 10)
            b = Bijectors.bijector(dist)
            test_θ_transformed = 10
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            model_def = @bugs begin
                a ~ dbin(0.1, 10)
            end
            transformed_model = compile(model_def, NamedTuple(), (a=test_θ,))
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            # the bijector of dbin is the identity, so the log density should be the same
            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end

        @testset "dgamma (Gamma)" begin
            dist = dgamma(0.001, 0.001)
            b = Bijectors.bijector(dist)
            test_θ_transformed = 10
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            model_def = @bugs begin
                a ~ dgamma(0.001, 0.001)
            end
            transformed_model = compile(model_def, NamedTuple(), (a=test_θ,))
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end

        @testset "ddirich (Dirichlet)" begin
            # create valid test input
            alpha = rand(10)
            dist = ddirich(alpha)
            b = Bijectors.bijector(dist)
            test_θ_transformed = rand(9)
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            model_def = @bugs begin
                x[1:10] ~ ddirich(alpha[1:10])
            end
            transformed_model = compile(model_def, (alpha=alpha,), (x=test_θ,))
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end

        @testset "dwish (Wishart)" begin
            # create valid test input
            scale_matrix = randn(10, 10)
            scale_matrix = scale_matrix * transpose(scale_matrix)  # Ensuring positive-definiteness
            degrees_of_freedom = 12

            dist = dwish(scale_matrix, degrees_of_freedom)
            b = Bijectors.bijector(dist)
            test_θ_transformed = rand(55)
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            model_def = @bugs begin
                x[1:10, 1:10] ~ dwish(scale_matrix[:, :], degrees_of_freedom)
            end
            transformed_model = compile(
                model_def,
                (degrees_of_freedom=degrees_of_freedom, scale_matrix=scale_matrix),
                (x=test_θ,),
            )
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end

        @testset "lkj (LKJ)" begin
            dist = LKJ(10, 0.5)
            b = Bijectors.bijector(dist)
            test_θ_transformed = rand(45)
            test_θ = Bijectors.inverse(b)(test_θ_transformed)

            reference_logp_untransformed = logpdf(dist, test_θ)
            reference_logp_transformed =
                logpdf(dist, test_θ) +
                logabsdetjac(Bijectors.inverse(b), test_θ_transformed)

            model_def = @bugs begin
                x[1:10, 1:10] ~ LKJ(10, 0.5)
            end
            transformed_model = compile(model_def, NamedTuple(), (x=test_θ,))
            untransformed_model = JuliaBUGS.settrans(transformed_model, false)

            @test LogDensityProblems.dimension(untransformed_model) == 100
            @test LogDensityProblems.dimension(transformed_model) == 45

            @test _logjoint(untransformed_model) ≈ reference_logp_untransformed rtol = 1E-6
            @test _logjoint(transformed_model) ≈ reference_logp_transformed rtol = 1E-6

            @test LogDensityProblems.logdensity(
                transformed_model, JuliaBUGS.getparams(transformed_model)
            ) ≈ reference_logp_transformed rtol = 1E-6
            @test LogDensityProblems.logdensity(
                untransformed_model, JuliaBUGS.getparams(untransformed_model)
            ) ≈ reference_logp_untransformed rtol = 1E-6
        end
    end
end

@testset "Log density of BUGS models" begin
    @testset "rats" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1.rats
        transformed_model = compile(model_def, data, inits)
        untransformed_model = JuliaBUGS.settrans(transformed_model, false)
        @test _logjoint(untransformed_model) ≈ -174029.38703951868 rtol = 1E-6
        @test _logjoint(transformed_model) ≈ -174029.38703951868 rtol = 1E-6

        @test LogDensityProblems.logdensity(
            transformed_model, JuliaBUGS.getparams(transformed_model)
        ) ≈ -174029.38703951868 rtol = 1E-6
        @test LogDensityProblems.logdensity(
            untransformed_model, JuliaBUGS.getparams(untransformed_model)
        ) ≈ -174029.38703951868 rtol = 1E-6
    end

    @testset "blockers" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1.blockers
        transformed_model = compile(model_def, data, inits)
        untransformed_model = JuliaBUGS.settrans(transformed_model, false)

        @test _logjoint(untransformed_model) ≈ -8418.416388326123 rtol = 1E-6
        @test _logjoint(transformed_model) ≈ -8418.416388326123 rtol = 1E-6

        @test LogDensityProblems.logdensity(
            transformed_model, JuliaBUGS.getparams(transformed_model)
        ) ≈ -8418.416388326123 rtol = 1E-6
        @test LogDensityProblems.logdensity(
            untransformed_model, JuliaBUGS.getparams(untransformed_model)
        ) ≈ -8418.416388326123 rtol = 1E-6
    end

    @testset "bones" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1.bones
        transformed_model = compile(model_def, data, inits)
        untransformed_model = JuliaBUGS.settrans(transformed_model, false)

        @test _logjoint(untransformed_model) ≈ -161.6492002285034 rtol = 1E-6
        @test _logjoint(transformed_model) ≈ -161.6492002285034 rtol = 1E-6

        @test LogDensityProblems.logdensity(
            transformed_model, JuliaBUGS.getparams(transformed_model)
        ) ≈ -161.6492002285034 rtol = 1E-6
        @test LogDensityProblems.logdensity(
            untransformed_model, JuliaBUGS.getparams(untransformed_model)
        ) ≈ -161.6492002285034 rtol = 1E-6
    end

    @testset "dogs" begin
        (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1.dogs
        transformed_model = compile(model_def, data, inits)
        untransformed_model = JuliaBUGS.settrans(transformed_model, false)

        @test _logjoint(untransformed_model) ≈ -1243.188922285352 rtol = 1E-6
        @test _logjoint(transformed_model) ≈ -1243.3996613167667 rtol = 1E-6

        @test LogDensityProblems.logdensity(
            transformed_model, JuliaBUGS.getparams(transformed_model)
        ) ≈ -1243.3996613167667 rtol = 1E-6
        @test LogDensityProblems.logdensity(
            untransformed_model, JuliaBUGS.getparams(untransformed_model)
        ) ≈ -1243.188922285352 rtol = 1E-6
    end
end

## transcribed BUGS models in DynamicPPL

# # rats
# @model function rats(Y, x, xbar, N, T)
#     var"tau.c" ~ dgamma(0.001, 0.001)
#     sigma = 1 / sqrt(var"tau.c")

#     var"alpha.c" ~ dnorm(0.0, 1.0E-6)
#     var"alpha.tau" ~ dgamma(0.001, 0.001)

#     var"beta.c" ~ dnorm(0.0, 1.0E-6)
#     var"beta.tau" ~ dgamma(0.001, 0.001)

#     alpha0 = var"alpha.c" - xbar * var"beta.c"

#     alpha = Vector{Real}(undef, N)
#     beta = Vector{Real}(undef, N)

#     for i in 1:N
#         alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
#         beta[i] ~ dnorm(var"beta.c", var"beta.tau")

#         for j in 1:T
#             mu = alpha[i] + beta[i] * (x[j] - xbar)
#             Y[i, j] ~ dnorm(mu, var"tau.c")
#         end
#     end

#     return sigma, alpha0
# end

# (; N, T, x, xbar, Y) = data
# model = rats(Y, x, xbar, N, T)

# # blockers
# @model function blockers(rc, rt, nc, nt, Num)
#     d ~ dnorm(0.0, 1.0E-6)
#     tau ~ dgamma(0.001, 0.001)

#     mu = Vector{Real}(undef, Num)
#     delta = Vector{Real}(undef, Num)
#     pc = Vector{Real}(undef, Num)
#     pt = Vector{Real}(undef, Num)

#     for i in 1:Num
#         mu[i] ~ dnorm(0.0, 1.0E-5)
#         delta[i] ~ dnorm(d, tau)

#         pc[i] = logistic(mu[i])
#         pt[i] = logistic(mu[i] + delta[i])

#         rc[i] ~ dbin(pc[i], nc[i])
#         rt[i] ~ dbin(pt[i], nt[i])
#     end

#     var"delta.new" ~ dnorm(d, tau)
#     sigma = 1 / sqrt(tau)

#     return sigma
# end

# (; rt, nt, rc, nc, Num) = data
# model = blockers(rc, rt, nc, nt, Num)

# # bones
# @model function bones(grade, nChild, nInd, ncat, gamma, delta)
#     theta = Vector{Real}(undef, nChild)
#     Q = Array{Real}(undef, nChild, nInd, maximum(ncat))
#     p = Array{Real}(undef, nChild, nInd, maximum(ncat))
#     cumulative_grade = Array{Real}(undef, nChild, nInd)

#     for i in 1:nChild
#         theta[i] ~ dnorm(0.0, 0.001)

#         for j in 1:nInd
#             for k in 1:(ncat[j] - 1)
#                 Q[i, j, k] = logistic(delta[j] * (theta[i] - gamma[j, k]))
#             end
#         end

#         for j in 1:nInd
#             p[i, j, 1] = 1 - Q[i, j, 1]

#             for k in 2:(ncat[j] - 1)
#                 p[i, j, k] = Q[i, j, k - 1] - Q[i, j, k]
#             end

#             p[i, j, ncat[j]] = Q[i, j, ncat[j] - 1]
#             grade[i, j] ~ dcat(p[i, j, 1:ncat[j]])
#         end
#     end
# end

# (; grade, nChild, nInd, ncat, gamma, delta) = data
# model = bones(grade, nChild, nInd, ncat, gamma, delta)

# # dogs

# @model function dogs(Dogs, Trials, Y, y)
#     # Initialize matrices
#     xa = zeros(Dogs, Trials)
#     xs = zeros(Dogs, Trials)
#     p = zeros(Dogs, Trials)

#     # Flat priors for alpha and beta, restricted to (-∞, -0.00001)
#     alpha ~ dunif(-10, -1.0e-5)
#     beta ~ dunif(-10, -1.0e-5)

#     for i in 1:Dogs
#         xa[i, 1] = 0
#         xs[i, 1] = 0
#         p[i, 1] = 0

#         for j in 2:Trials
#             xa[i, j] = sum(Y[i, 1:(j - 1)])
#             xs[i, j] = j - 1 - xa[i, j]
#             p[i, j] = exp(alpha * xa[i, j] + beta * xs[i, j])
#             # The Bernoulli likelihood
#             y[i, j] ~ dbern(p[i, j])
#         end
#     end

#     # Transformation to positive values
#     A = exp(alpha)
#     B = exp(beta)

#     return A, B
# end

# (; Dogs, Trials, Y) = data
# model = dogs(Dogs, Trials, Y, 1 .- Y)
