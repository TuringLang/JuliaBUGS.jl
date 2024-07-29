"""
    generate_expr(model::BUGSModel)

Generate a Julia function that takes a NamedTuple represent the env and vector of parameter values, returns the computed log density.
"""
function generate_expr(model::BUGSModel)
    expr = Expr(:block)

    push!(expr.args, :(logp = 0.0))
    push!(
        expr.args,
        Expr(
            :(=),
            Expr(:tuple, Expr(:parameters, collect(keys(model.varinfo.values))...)),
            :value_nt,
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
                push!(
                    expr.args,
                    Expr(
                        :(=),
                        :logp,
                        Expr(
                            :call,
                            :+,
                            :logp,
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
                push!(
                    expr.args,
                    Expr(
                        :(=),
                        :dist,
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
                            val_and_logjac = DynamicPPL.with_logabsdet_jacobian_and_reconstruct(
                                Bijectors.inverse(bijector(dist)),
                                dist,
                                params[($current_idx):($current_idx + $l - 1)],
                            )
                        ),
                    )
                    push!(expr.args, :($vn_expr = val_and_logjac[1]))
                    push!(
                        expr.args,
                        :(logp = logp + logpdf(dist, $vn_expr) + val_and_logjac[2]),
                    )
                else
                    push!(
                        expr.args,
                        :(
                            $vn_expr = DynamicPPL.reconstruct(
                                dist, params[($current_idx):($current_idx + $l - 1)]
                            )
                        ),
                    )
                    push!(expr.args, :(logp = logp + logpdf(dist, $vn_expr)))
                end
                current_idx += l
            end
        end
    end

    push!(expr.args, :(return logp))

    return Expr(:function, Expr(:tuple, :value_nt, :params), expr)
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

f_ex = generate_expr(model)
f = eval(f_ex)

params = rand(2)
f(model.varinfo.values, params)
using LogDensityProblems
LogDensityProblems.logdensity(model, params)

using BenchmarkTools
@benchmark f(model.varinfo.values, params)
@benchmark LogDensityProblems.logdensity(model, params)
