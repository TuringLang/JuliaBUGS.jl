function to_sampler(model, free_vars...; fixed_vars...)
    transformed_lines = _to_sampler(model).args
    fixed_defs = [:($n = $v) for (n, v) in fixed_vars]
    return quote
        $(fixed_defs...)
        $(transformed_lines...)
        return (; $(free_vars...))
    end
end

_to_sampler(x) = x
function _to_sampler(expr::Expr)
    if Meta.isexpr(expr, :~, 2)
        lhs, rhs = expr.args
        return :($lhs = rand($(_to_sampler(rhs))))
    elseif Meta.isexpr(expr, [:truncated, :censored], 3)
        return Expr(:call, expr.head, expr.args...)
    else
        return Expr(expr.head, _to_sampler.(expr.args)...)
    end
end



function to_density(model, free_vars...; fixed_vars...)
    transformed_lines = _to_density(model).args
    fixed_defs = [:($n = $v) for (n, v) in fixed_vars]
    return quote
        function ($(free_vars...),)
            __target__ = 0.0
            $(fixed_defs...)
            $(transformed_lines...)
            return __target__
        end
    end
end

_to_density(x) = x
function _to_density(expr::Expr)
    if Meta.isexpr(expr, :~, 2)
        lhs, rhs = expr.args
        return :(__target__ += logpdf($(_to_density(rhs)), $lhs))
    elseif Meta.isexpr(expr, [:truncated, :censored], 3)
        return Expr(:call, expr.head, expr.args...)
    else
        return Expr(expr.head, _to_density.(expr.args)...)
    end
end

# julia> m2
# quote
#     $(Expr(:~, :μ, :(Normal())))
#     for i = 1:N
#         $(Expr(:~, :(x[i]), :(Normal(μ))))
#     end
# end

# julia> string(LineNumberNode(10, nothing))^C

# julia> to_sampler(m2, :x, :μ; N = 3)
# quote
#     #= /home/philipp/git/BugsModels/examples/evaluation.jl:5 =#
#     N = 3
#     #= /home/philipp/git/BugsModels/examples/evaluation.jl:6 =#
#     μ = rand(Normal())
#     for i = 1:N
#         x[i] = rand(Normal(μ))
#     end
#     #= /home/philipp/git/BugsModels/examples/evaluation.jl:7 =#
#     return (; x, μ)
# end

# julia> to_density(m2, :μ; x = rand(3), N = 3)
# quote
#     #= /home/philipp/git/BugsModels/examples/evaluation.jl:29 =#
#     function (μ,)
#         #= /home/philipp/git/BugsModels/examples/evaluation.jl:29 =#
#         #= /home/philipp/git/BugsModels/examples/evaluation.jl:30 =#
#         __target__ = 0.0
#         #= /home/philipp/git/BugsModels/examples/evaluation.jl:31 =#
#         x = [0.8700954931560619, 0.08379104605847298, 0.07346752731832884]
#         N = 3
#         #= /home/philipp/git/BugsModels/examples/evaluation.jl:32 =#
#         __target__ += logpdf(Normal(), μ)
#         for i = 1:N
#             __target__ += logpdf(Normal(μ), x[i])
#         end
#         #= /home/philipp/git/BugsModels/examples/evaluation.jl:33 =#
#         return __target__
#     end
# end

