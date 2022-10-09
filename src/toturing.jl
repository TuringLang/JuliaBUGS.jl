using Turing
using MacroTools
using Distributions

function toturing(g::BUGSGraph)
    expr = []
    args = Dict()
    for n in getsortednodes(g)
        funcall = deepcopy(g.nodefunc[n].args[2])
        if isa(funcall, Expr)
            funcall.args[1] = Expr(:., :SymbolicPPL, QuoteNode(funcall.args[1]))
            push!(expr, Expr(:call, :(~), g.reverse_nodeenum[n], funcall))
        elseif isa(funcall, Distributions.Distribution)
            funcall = Expr(:call, nameof(typeof(funcall)), Distributions.params(funcall)...)
            push!(expr, Expr(:call, :(~), g.reverse_nodeenum[n], funcall))
        end
    end
    args = []
    for a in g.observed_values
        push!(args, Expr(:kw, g.reverse_nodeenum[a[1]], a[2]))
    end
    ex = Expr(:function, Expr(:call, :bugsturing, Expr(:parameters, args...)), Expr(:block, expr...))
    turing_expr = Turing.DynamicPPL.model(@__MODULE__, LineNumberNode(@__LINE__, @__FILE__), ex, false)
    eval(turing_expr)
    return bugsturing # Potentially unsafe
end
