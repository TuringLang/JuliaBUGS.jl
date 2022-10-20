using DynamicPPL
using MacroTools
using Distributions
using MetaGraphsNext

function todppl(g::MetaDiGraph)
    expr = []
    args = Dict()
    sorted_nodes = (x->label_for(g, x)).(topological_sort_by_dfs(g))
    for n in sorted_nodes
        funccall = MacroTools.unresolve(deepcopy(g[n].func_expr))
        if isa(funccall, Expr)
            funccall.args[1] = Expr(:., :SymbolicPPL, QuoteNode(funccall.args[1]))
            push!(expr, Expr(:call, :(~), n, funccall))
        elseif isa(funccall, Distributions.Distribution)
            funccall = Expr(:call, nameof(typeof(funccall)), Distributions.params(funccall)...)
            push!(expr, Expr(:call, :(~), n, funccall))
        end
    end
    args = [Expr(:kw, a, g[a].data) for a in vertices(g) if g[a].is_data]
    ex = Expr(:function, Expr(:call, :model, Expr(:parameters, args...)), Expr(:block, expr...))
    # return ex
    eval(DynamicPPL.model(@__MODULE__, LineNumberNode(@__LINE__, @__FILE__), ex, false))
    return model
end
