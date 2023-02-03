include("c_2.jl");

using SymbolicPPL
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


rats_cond = rats(x, xbar, Y, N, T)
rand(rats_cond)

sample(rats_cond, NUTS(1000, 0.65), 10000)

vars, defs, dep_graph = program(model_def)
c = code_gen(vars, defs, dep_graph)

@test eval_expr(:(x + y * 2), Dict(:x=>1, :y=>2)) == 5
@test eval(:(g[2]), Dict(:g => [1, 2, 3])) == 2

variables(:(g[2] + x))

expr = :(Y[i, j] ~ dnorm(mu[i, j], tau_c))
expr = Expr(:~, expr.args[2:end]...)
vars, defs, dep_graph = Dict(), Dict(), SimpleDiGraph()
assignment!(expr, vars, defs, dep_graph, Dict(:i => 1, :j => 1))

expr = model_def.args[1]
data = Dict(:N => 2, :T => 2)
vars, defs, dep_graph = Dict(), Dict(), SimpleDiGraph()
for_loop!(expr, data, vars, defs, dep_graph)
vars

vars, defs, dep_graph, def_to_vars = program(model_def, data)
vars
defs
def_to_vars

expr = @bugsast begin
    for i in 1:10
        x[i] ~ dnorm(a, 1)
        x[i + 10] ~ dnorm(0, 1)
    end
    a = mean(x[11:20])
end

expr = @bugsast begin
    # BUGS program
    x[1] = 1
    for i in 2:10
        x[i] ~ dnorm(y[i-1], 1)
    end
    for i in 1:10
        y[i] ~ dnorm(x[i], 1)
    end
end

cd = CompilerData()
assignment!(:(x = y + z), cd)

cd = program(expr, Dict())
cd.vars

variables(:(x[i]), Dict(:i=>1))

replace_loop_var((:x, :(1+i)), Dict(:i => 1))

variables(:(x[1, 1:10, 2]), Dict())

m_g = loop_dep_detect(cd.def_to_vars, cd.dep_graph)

expr = @bugsast begin
    for i in 1:N
        for j in 1:i
            x[i, j] ~ dnorm(0, 1)
        end
    end
end

cd = program(expr, Dict(:N => 3))
cd.vars

g = SimpleDiGraph(5)
add_edge!(g, 1, 2)
add_edge!(g, 2, 3)
add_edge!(g, 3, 4)

vertices(g)
merge_vertices!(g, [2, 3])

new_nodes, new_dep_graph = loop_dep_detect(cd)
new_nodes
new_dep_graph

simplecycles(new_dep_graph)

using Plots, GraphRecipes
graphplot(new_dep_graph, curves=false, names=names)

vars = merge(cd.vars, new_nodes)
r_vars = Dict()
for (k, v) in vars
    r_vars[v] = k
end

graphplot(cd.dep_graph)

names = [r_vars[i] for i in vertices(new_dep_graph)]

#######################

# using Symbolics

# tosymbolic(x::Symbol) = (@variables $x)[1]
# tosymbolic(x::Number) = x
# tosymbolic(e::Expr) = eval(e.args[1])(tosymbolic(e.args[2]), tosymbolic(e.args[3]))

# tosymbolic(:(x + y * (z + 1)))