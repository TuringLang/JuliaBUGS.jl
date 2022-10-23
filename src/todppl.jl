using Distributions
using DynamicPPL
using MacroTools
using Graphs, MetaGraphsNext

function todppl(g::MetaDiGraph)
    expr = []
    args = Dict()
    sorted_nodes = (x->label_for(g, x)).(topological_sort_by_dfs(g))
    for n in sorted_nodes
        f = g[n].f_expr.args[2] |> MacroTools.flatten |> MacroTools.unresolve
        if isa(f, Expr)
            f.args[1] = Expr(:., :SymbolicPPL, QuoteNode(f.args[1]))
            push!(expr, Expr(:call, :(~), n, f))
        elseif isa(f, Distributions.Distribution)
            f = Expr(:call, nameof(typeof(f)), Distributions.params(f)...)
            push!(expr, Expr(:call, :(~), n, f))
        end
    end
    args = [Expr(:kw, a, g[a].data) for a in (x->label_for(g,x)).(vertices(g)) if g[a].is_data]
    ex = Expr(:function, Expr(:call, :model, Expr(:parameters, args...)), Expr(:block, expr...))
    # println(ex)
    eval(DynamicPPL.model(@__MODULE__, LineNumberNode(@__LINE__, @__FILE__), ex, false))
    return model
end
