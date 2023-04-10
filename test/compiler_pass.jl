using JuliaBUGS
using JuliaBUGS: Var, program!, CollectVariables, NodeFunctions
using UnPack

## Linear regression
model_def = @bugsast begin
    for i in 1:N
        Y[i] ~ dnorm(μ[i], τ)
        μ[i] = α + β * (x[i] - xbar)
    end
    τ ~ dgamma(0.001, 0.001)
    σ = 1 / sqrt(τ)
    logτ = log(τ)
    α = dnorm(0.0, 1e-6)
    β = dnorm(0.0, 1e-6)
end

data = (x=[1, 2, 3, 4, 5], Y=[1, 3, 3, 3, 5], xbar = 3, N=5)

## Rats
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

inits = Dict(
    :alpha => alpha,
    :beta => beta,
    :alpha_c => alpha_c,
    :beta_c => beta_c,
    :tau_c => tau_c,
    :alpha_tau => alpha_tau,
    :beta_tau => beta_tau,
);
##
include("/home/sunxd/JuliaBUGS.jl/src/BUGSExamples/Volume_I/Bones.jl");
model_def = bones.model_def;
data = Dict(pairs(bones.data));
inits = Dict(pairs(bones.inits[1]));


##

vars, array_sizes, transformed_variables, array_bitmap = program!(CollectVariables(), model_def, data);
pass = program!(NodeFunctions(vars, array_sizes, array_bitmap), model_def, data);
@unpack vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = pass
