using JuliaBUGS: WithinGibbs, MHFromPrior, HMCSampler

@testset "Simple gibbs" begin
    model_def = @bugs begin
        # Likelihood
        for i in 1:N
            y[i] ~ dnorm(mu[i], tau)
            mu[i] = alpha + beta * x[i]
        end

        # Priors
        alpha ~ dnorm(0, 0.01)
        beta ~ dnorm(0, 0.01)
        sigma ~ dunif(0, 10)

        # Precision
        tau = pow(sigma, -2)

        # Generated Quantities for testing purposes
        gen_quant = alpha + beta * sigma
    end

    # ground truth: alpha = 3, beta = 2, sigma = 1
    data = (
        N=10,
        x=[0.0, 1.11, 2.22, 3.33, 4.44, 5.56, 6.67, 7.78, 8.89, 10.0],
        y=[1.58, 4.80, 7.10, 8.86, 11.73, 14.52, 18.22, 18.73, 21.04, 22.93],
    )

    model = compile(model_def, data, (;))
    # use NamedTuple for SimpleVarinfo
    model = @set model.varinfo = begin
        vi = model.varinfo
        SimpleVarInfo(DynamicPPL.values_as(vi, NamedTuple), vi.logp, vi.transformation)
    end

    # single step
    p_s, st_init = AbstractMCMC.step(
        Random.default_rng(),
        AbstractMCMC.LogDensityModel(model),
        WithinGibbs(MHFromPrior()),
    )

    # following step
    p_s, st = AbstractMCMC.step(
        Random.default_rng(),
        AbstractMCMC.LogDensityModel(model),
        WithinGibbs(MHFromPrior()),
        st_init,
    )

    sample_size = 10000
    chn = AbstractMCMC.sample(
        Random.default_rng(),
        model,
        WithinGibbs(MHFromPrior()),
        sample_size;
        discard_initial=Int(sample_size / 2),
    )
    @test chn.name_map[:parameters] == [
        :sigma
        :beta
        :alpha
        :gen_quant
    ]
    means = mean(chn)
    @test means[:alpha].nt.mean[1] ≈ 2.3 atol = 0.2
    @test means[:beta].nt.mean[1] ≈ 2.1 atol = 0.2
    @test means[:sigma].nt.mean[1] ≈ 0.9 atol = 0.2
    @test means[:gen_quant].nt.mean[1] ≈ 4.2 atol = 0.2

    sample_size = 1000
    hmc_chn = AbstractMCMC.sample(
        Random.default_rng(),
        model,
        WithinGibbs(JuliaBUGS.HMCSampler()),
        sample_size;
        discard_initial=Int(sample_size / 2),
    )
    means = mean(hmc_chn)
    @test means[:alpha].nt.mean[1] ≈ 2.3 atol = 0.2
    @test means[:beta].nt.mean[1] ≈ 2.1 atol = 0.2
    @test means[:sigma].nt.mean[1] ≈ 0.9 atol = 0.2
    @test means[:gen_quant].nt.mean[1] ≈ 4.2 atol = 0.2
end
