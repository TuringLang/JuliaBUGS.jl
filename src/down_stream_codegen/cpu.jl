"""
    generate_expr(model::BUGSModel)

Generate a Julia function that takes a NamedTuple represent the env and 
vector of parameter values, returns the computed log density.

# Examples
```julia-repl
julia > model_def = @bugs begin
    x[1:2] ~ dmnorm(zeros(2), eye[1:2, 1:2])
    y ~ dnorm(x[1], 1)
    u[1] ~ dnorm(x[2], 1)
    w = y + u[1]
    u[2] ~ dnorm(w, 1)
end
quote
    x[1:2] ~ dmnorm(zeros(2), eye[1:2, 1:2])
    y ~ dnorm(x[1], 1)
    u[1] ~ dnorm(x[2], 1)
    w = y + u[1]
    u[2] ~ dnorm(w, 1)
end

julia> model = compile(model_def, (; x=[1.0, 2.0], eye=[1 0; 0 1]))
BUGSModel (transformed, with dimension 3):

  Parameters of the model:
    u[1], y, u[2]

  Values:
(w = 1.8684132156092446, y = 0.7687440709366652, u = [1.0996691446725793, 2.2946374552395965], eye = [1 0; 0 1], x = [1.0, 2.0])

julia> generate_expr(model)
:(function (var"##value_nt#260", var"##params#261")
      var"##logp#256" = 0.0
      (; w, y, u, eye, x) = var"##value_nt#260"
      var"##dist#257" = (JuliaBUGS.var"#165#167"())(x = x)
      var"##val_and_logjac#258" = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(JuliaBUGS.Bijectors.inverse(JuliaBUGS.Bijectors.bijector(var"##dist#257")), var"##dist#257", var"##params#261"[1:(1 + 1) - 1])
      u[1] = var"##val_and_logjac#258"[1]
      var"##logp#256" = var"##logp#256" + logpdf(var"##dist#257", u[1]) + var"##val_and_logjac#258"[2]
      var"##dist#257" = (JuliaBUGS.var"#162#164"())(x = x)
      var"##val_and_logjac#258" = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(JuliaBUGS.Bijectors.inverse(JuliaBUGS.Bijectors.bijector(var"##dist#257")), var"##dist#257", var"##params#261"[2:(2 + 1) - 1])
      y = var"##val_and_logjac#258"[1]
      var"##logp#256" = var"##logp#256" + logpdf(var"##dist#257", y) + var"##val_and_logjac#258"[2]
      w = (JuliaBUGS.var"#168#170"())(y = y, u = u)
      var"##dist#257" = (JuliaBUGS.var"#171#173"())(w = w)
      var"##val_and_logjac#258" = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(JuliaBUGS.Bijectors.inverse(JuliaBUGS.Bijectors.bijector(var"##dist#257")), var"##dist#257", var"##params#261"[3:(3 + 1) - 1])
      u[2] = var"##val_and_logjac#258"[1]
      var"##logp#256" = var"##logp#256" + logpdf(var"##dist#257", u[2]) + var"##val_and_logjac#258"[2]
      var"##logp#256" = var"##logp#256" + logpdf((JuliaBUGS.var"#159#161"())(eye = eye), x[1:2])
      return var"##logp#256"
  end)
```
"""
function generate_expr(model::BUGSModel)
    # gensyms for intermediate variables to avoid name conflicts with user-defined variables
    _logp = gensym(:logp)
    _dist = gensym(:dist)
    _val_and_logjac = gensym(:val_and_logjac)
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
        vn_expr = get_vn_expr(vn)
        (; is_stochastic, is_observed, node_function, node_args, loop_vars) = model.g[vn]
        if !is_stochastic
            # if the node is not stochastic, just eval and bind
            push!(
                expr.args,
                Expr(
                    :(=),
                    vn_expr,
                    generate_function_call_expr(node_function, node_args, loop_vars),
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
                                :(JuliaBUGS.Distributions.logpdf),
                                generate_function_call_expr(
                                    node_function, node_args, loop_vars
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
                        generate_function_call_expr(node_function, node_args, loop_vars),
                    ),
                )
                l = var_lengths[vn]
                if model.transformed
                    push!(
                        expr.args,
                        :(
                            $_val_and_logjac = JuliaBUGS.DynamicPPL.with_logabsdet_jacobian_and_reconstruct(
                                JuliaBUGS.Bijectors.inverse(
                                    JuliaBUGS.Bijectors.bijector($_dist)
                                ),
                                $_dist,
                                $_params[($current_idx):($current_idx + $l - 1)],
                            )
                        ),
                    )
                    push!(expr.args, :($vn_expr = $_val_and_logjac[1]))
                    push!(
                        expr.args,
                        :(
                            $_logp =
                                $_logp +
                                JuliaBUGS.Distributions.logpdf($_dist, $vn_expr) +
                                $_val_and_logjac[2]
                        ),
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

"""
    get_vn_expr(vn::VarName)

Generate a Julia expression for the variable name.

# Examples

```jldoctest
julia> JuliaBUGS.get_vn_expr(@varname(a))
:a

julia> JuliaBUGS.get_vn_expr(@varname(a.b))
Symbol("a.b")

julia> JuliaBUGS.get_vn_expr(@varname(a[1]))
:(a[1])

julia> JuliaBUGS.get_vn_expr(@varname(var"a.b"[1]))
:(var"a.b"[1])
```
"""
function get_vn_expr(vn::VarName)
    vn_string = string(Symbol(vn))
    # if there is a . in the string, like "a.b" (R style name), then wrap in var"a.b"
    if occursin(".", vn_string)
        # if a array index, only wrap the array name
        if occursin("[", vn_string)
            array_name, index = split(vn_string, "["; limit=2)
            vn_string = "var\"$(array_name)\"[$(index)"
        else
            vn_string = "var\"$vn_string\""
        end
    end
    return Meta.parse(vn_string)
end

function generate_function_call_expr(node_function, node_args, loop_vars)
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
