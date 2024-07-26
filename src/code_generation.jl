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
                # this is kind of the difficult part:
                # the counter approach is hard to code this way
                # we should just do an unflatten

                # next issue is about logabsdetjac
            end
        end
    end

    return expr
end

# I think this will be limited by the dictionary accesses
# of course, another issue is allocation, will be an issue when dimension is high
function unflatten(model::BUGSModel, params::Vector{Float64})
    unflattened_params = Vector{Vector{Float64}}()
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end
    index = 1
    for vn in model.parameters
        push!(unflattened_params, params[index:index+var_lengths[vn]-1])
        index += var_lengths[vn]
    end

    return unflattened_params
end

function compute_dims_vec(model::BUGSModel)
    dims = Int[]
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end
    for vn in model.parameters
        push!(dims, var_lengths[vn])
    end
    return dims
end
dims = compute_dims_vec(model)
function unflatten_w_dims(dims::Vector{Int}, params::Vector{Float64})
    unflattened_params = Vector{Vector{Float64}}()
    index = 1
    for dim in dims
        push!(unflattened_params, params[index:index+dim-1])
        index += dim
    end
    return unflattened_params
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
