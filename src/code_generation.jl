"""
    generate_expr(model::BUGSModel)

Generate a Julia function that takes a NamedTuple represent the env and 
vector of parameter values, returns the computed log density.
"""
function generate_expr(model::BUGSModel)
    # gensyms for intermediate variables to avoid name conflicts with user-defined variables
    _logp = gensym(:logp)
    _dist = gensym(:dist)
    _val_and_logjac = gensym(:val_and_logjac)
    _current_idx = gensym(:current_idx)
    _value_nt = gensym(:value_nt)
    _params = gensym(:params)

    # start with an empty function body
    expr = Expr(:block)
    push!(expr.args, :($_logp = 0.0))
    # unpack the values from the env(NamedTuple)
    push!(
        expr.args,
        Expr(
            :(=),
            Expr(:tuple, Expr(:parameters, collect(keys(model.varinfo.values))...)),
            _value_nt,
        ),
    )
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end
    current_idx = 1
    for vn in model.sorted_nodes
        vn_expr = Meta.parse(string(Symbol(vn)))
        (; is_stochastic, is_observed, node_function_expr, node_function, node_args, loop_vars) = model.g[vn]
        if !is_stochastic
            # if the node is not stochastic, just eval and bind
            push!(
                expr.args,
                Expr(
                    :(=),
                    vn_expr,
                    generate_function_call_expr(
                        vn_expr, node_function, node_args, loop_vars
                    ),
                ),
            )
        else
            if is_observed
                # accumulate the log density of the observed node
                push!(
                    expr.args,
                    Expr(
                        :(=),
                        _logp,
                        Expr(
                            :call,
                            :+,
                            _logp,
                            Expr(
                                :call,
                                :logpdf,
                                generate_function_call_expr(
                                    vn_expr, node_function, node_args, loop_vars
                                ),
                                vn_expr,
                            ),
                        ),
                    ),
                )
            else
                # if the variable is stochastic but not observed, first eval the distribution, then fetch values from the params vector
                push!(
                    expr.args,
                    Expr(
                        :(=),
                        _dist,
                        generate_function_call_expr(
                            vn_expr, node_function, node_args, loop_vars
                        ),
                    ),
                )
                l = var_lengths[vn]
                if model.transformed
                    push!(
                        expr.args,
                        :(
                            $_val_and_logjac = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(
                                Bijectors.inverse(bijector($_dist)),
                                $_dist,
                                $_params[($current_idx):($current_idx + $l - 1)],
                            )
                        ),
                    )
                    push!(expr.args, :($vn_expr = $_val_and_logjac[1]))
                    push!(
                        expr.args,
                        :($_logp = $_logp + logpdf($_dist, $vn_expr) + $_val_and_logjac[2]),
                    )
                else
                    push!(
                        expr.args,
                        :(
                            $vn_expr = JuliaBUGS.DynamicPPL.reconstruct(
                                $_dist, $_params[($current_idx):($current_idx + $l - 1)]
                            )
                        ),
                    )
                    push!(expr.args, :($_logp = $_logp + logpdf($_dist, $vn_expr)))
                end
                current_idx += l
            end
        end
    end

    push!(expr.args, :(return $_logp))

    return Expr(:function, Expr(:tuple, _value_nt, _params), expr)
end

# `node_function` here is a function
function generate_function_call_expr(vn_expr, node_function, node_args, loop_vars)
    return Expr(
        :call,
        node_function,
        [
            Expr(
                :kw,
                node_arg,
                if node_arg in keys(loop_vars)
                    loop_vars[node_arg]
                else
                    node_arg
                end,
            ) for node_arg in node_args
        ]...,
    )
end

## test

using JuliaBUGS
using JuliaBUGS: BUGSModel

model_def = @bugs begin
    x ~ dnorm(0, 1)
    y ~ dnorm(x, 1)
    z = x + y
    w ~ dnorm(z, 1)
end

model = compile(model_def, (; x=1.0,))

model_def = @bugs begin
    x[1:2] ~ dmnorm(zeros(2), eye[1:2, 1:2])
    y ~ dnorm(x[1], 1)
    u[1] ~ dnorm(x[2], 1)
    w = y + u[1]
    u[2] ~ dnorm(w, 1)
end

model = compile(model_def, (; x=[1.0, 2.0], eye=[1 0; 0 1]))

f_ex = generate_expr(model)
f = eval(f_ex)

params = rand(2)
params = rand(3)
f(model.varinfo.values, params)
using LogDensityProblems
LogDensityProblems.logdensity(model, params)

JuliaBUGS.@register_primitive I(d) = Matrix{Float64}(I, d, d)

using BenchmarkTools
@benchmark f(model.varinfo.values, params)
@benchmark LogDensityProblems.logdensity(model, params)
