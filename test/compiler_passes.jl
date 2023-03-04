using Graphs, JuliaBUGS, Distributions
using JuliaBUGS:
    CollectVariables,
    DependencyGraph,
    NodeFunctions,
    ArrayElement,
    ArraySlice,
    ArrayVariable,
    program!,
    compile

#
model_def = @bugsast begin
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(mu[i, j], tau_c)
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(alpha_c, alpha_tau)
        beta[i] ~ dnorm(beta_c, beta_tau)
    end
    tau_c ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau_c)
    alpha_c ~ dnorm(0.0, 1.0E-6)
    alpha_tau ~ dgamma(0.001, 0.001)
    beta_c ~ dnorm(0.0, 1.0E-6)
    beta_tau ~ dgamma(0.001, 0.001)
    alpha0 = alpha_c - xbar * beta_c
end

# data
x = [8.0, 15.0, 22.0, 29.0, 36.0]
xbar = 22
N = 30
T = 5
Y = [
    151 199 246 283 320
    145 199 249 293 354
    147 214 263 312 328
    155 200 237 272 297
    135 188 230 280 323
    159 210 252 298 331
    141 189 231 275 305
    159 201 248 297 338
    177 236 285 350 376
    134 182 220 260 296
    160 208 261 313 352
    143 188 220 273 314
    154 200 244 289 325
    171 221 270 326 358
    163 216 242 281 312
    160 207 248 288 324
    142 187 234 280 316
    156 203 243 283 317
    157 212 259 307 336
    152 203 246 286 321
    154 205 253 298 334
    139 190 225 267 302
    146 191 229 272 302
    157 211 250 285 323
    132 185 237 286 331
    160 207 257 303 345
    169 216 261 295 333
    157 205 248 289 316
    137 180 219 258 291
    153 200 244 286 324
]

data = Dict(:x => x, :xbar => xbar, :Y => Y, :N => N, :T => T)

# initializations
alpha = ones(Integer, 30) .* 250
beta = ones(Integer, 30) .* 6
alpha_c = 150
beta_c = 10
tau_c = 1
alpha_tau = 1
beta_tau = 1

initializations = Dict(
    :alpha => alpha,
    :beta => beta,
    :alpha_c => alpha_c,
    :beta_c => beta_c,
    :tau_c => tau_c,
    :alpha_tau => alpha_tau,
    :beta_tau => beta_tau,
);

##

p = compile(model_def, data, initializations);
params = JuliaBUGS.gen_init_params(p)
p(JuliaBUGS.transform_and_flatten(trace, parameters, p.bijectors))

##
using AdvancedHMC
using ReverseDiff

D = length(initial_θ)
n_samples, n_adapts = 2000, 1000

metric = DiagEuclideanMetric(D)
hamiltonian = Hamiltonian(metric, p, :ReverseDiff)

initial_ϵ = find_good_stepsize(hamiltonian, initial_θ)
integrator = Leapfrog(initial_ϵ)
proposal = NUTS{MultinomialTS, GeneralisedNoUTurn}(integrator)
adaptor = StanHMCAdaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(0.8, integrator))

samples, stats = sample(hamiltonian, proposal, initial_θ, n_samples, adaptor, n_adapts; drop_warmup=true, progress=true)
##

beta_c_samples = [samples[s][64] for s in 1:length(samples)]
stats = mean(beta_c_samples), std(beta_c_samples) # Reference result: mean 6.186, variance 0.1088
