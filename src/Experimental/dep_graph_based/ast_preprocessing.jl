function cumulative(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = cumulative(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :cdf
            sub_expr.args[2].args[2] = dist
            return sub_expr
        else
            return sub_expr
        end
    end
end

function density(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = density(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :pdf
            sub_expr.args[2].args[2] = dist
            return sub_expr
        else
            return sub_expr
        end
    end
end

function deviance(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = deviance(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :logpdf
            sub_expr.args[2].args[2] = dist
            sub_expr.args[2] = Expr(:call, :*, -2, sub_expr.args[2])
            return sub_expr
        else
            return sub_expr
        end
    end
end

function find_tilde_rhs(expr::Expr, target::Union{Expr,Symbol})
    dist = nothing
    MacroTools.postwalk(expr) do sub_expr
        if isexpr(sub_expr, :(~))
            if sub_expr.args[1] == target
                isnothing(dist) || error("Exist two assignments to the same variable.")
                dist = sub_expr.args[2]
            end
        end
        return sub_expr
    end
    isnothing(dist) && error(
        "Error handling cumulative expression: can't find a stochastic assignment for $target.",
    )
    return dist
end

function linkfunction(expr::Expr)
    # link functions in stochastic assignments will be handled later
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, f_(lhs_) = rhs_)
            if f in keys(INVERSE_LINK_FUNCTION)
                sub_expr.args[1] = lhs
                sub_expr.args[2] = Expr(:call, INVERSE_LINK_FUNCTION[f], rhs)
            else
                error("Link function $f not supported.")
            end
        end
        return sub_expr
    end
end

function censored(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :censored)
            l, u = sub_expr.args[2:3]

            if l != :nothing && u != :nothing
                return Expr(:call, :censored, sub_expr.args...)
            elseif l != :nothing
                return Expr(:call, :censored_with_lower, sub_expr.args[1], l)
            else # u != :nothing
                return Expr(:call, :censored_with_upper, sub_expr.args[1], u)
            end
        else
            return sub_expr
        end
    end
end

function truncated(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :truncated)
            l, u = sub_expr.args[2:3]

            if l != :nothing && u != :nothing
                return Expr(:call, :truncated, sub_expr.args...)
            elseif l != :nothing
                return Expr(:call, :truncated_with_lower, sub_expr.args[1], l)
            else # u != :nothing
                return Expr(:call, :truncated_with_upper, sub_expr.args[1], u)
            end
        else
            return sub_expr
        end
    end
end

function transform_expr(model_def::Expr)
    return deviance(density(cumulative(truncated(censored(linkfunction(model_def))))))
end
