"""
    generate_expr(model::BUGSModel)

Generate a Julia function that takes a NamedTuple represent the env and vector of parameter values, returns the computed log density.
"""
function generate_expr(model::BUGSModel)
    expr = Expr(:block)

    (; sorted_nodes,) = model

    for vn in sorted_nodes
        (; is_stochastic, is_observed, node_function_expr, node_function, node_args, loop_vars) = model.g[vn]
        if !is_stochastic
            push!(
                expr.args,
                generate_function_call_expr(vn, node_function, node_args, loop_vars),
            )
        else
            if is_observed
                push!(
                    expr.args,
                    Expr(
                        :call,
                        :(=),
                        Expr(
                            :call,
                            :+,
                            logp,
                            Expr(
                                :call,
                                logpdf,
                                generate_function_call_expr(
                                    vn, node_function, node_args, loop_vars
                                ),
                            ),
                            Meta.parse(string(Symbol(vn))),
                        ),
                    ),
                )
            else
                
            end
        end
    end

    return expr
end

function generate_function_call_expr(vn, node_function, node_args, loop_vars)
    vn_expr = Meta.parse(string(Symbol(vn)))
    return Expr(
        :(=),
        vn_expr,
        Expr(
            :call,
            node_function,
            Expr(
                :paraemters,
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
                ],
            ),
        ),
    )
end
