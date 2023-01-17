
function todppl(g::BUGSGraph, print_turing_program=true)
    expr = []
    args = Dict()
    sorted_nodes = (x -> label_for(g, x)).(topological_sort_by_dfs(g))
    for n in sorted_nodes
        f = MacroTools.flatten(g[n].f_expr.args[2])
        if isa(f, Expr)
            f.args[1] = Expr(:., :SymbolicPPL, QuoteNode(f.args[1]))
            push!(expr, Expr(:call, :(~), n, f))
        elseif isa(f, Distributions.Distribution)
            dist_func = nameof(typeof(f))
            if dist_func == :GenericMvTDist
                dist_func = :MvTDist
            elseif dist_func == :DiscreteNonParametric
                dist_func = :Categorical
            end
            f = Expr(:call, dist_func, Distributions.params(f)...)
            push!(expr, Expr(:call, :(~), n, f))
        end
    end
    args = [
        Expr(:kw, a, g[a].data) for
        a in (x -> label_for(g, x)).(vertices(g)) if g[a].is_data
    ]
    ex = Expr(
        :function, Expr(:call, :model, Expr(:parameters, args...)), Expr(:block, expr...)
    )
    eval(DynamicPPL.model(@__MODULE__, LineNumberNode(@__LINE__, @__FILE__), ex, false))
    print_turing_program && println(ex)
    return model
end

function gen_variation_partition(g::BUGSGraph)
    dist_types = dry_run(g)[1]
    dt = Dict{Any,Any}()
    for k in keys(dist_types)
        dt[k] = dist_types[k] <: Sampleable{<:VariateForm,Discrete}
    end

    discrete_vars = [k for k in keys(dt) if dt[k]]
    continuous_vars = [k for k in keys(dt) if !dt[k]]
    return discrete_vars, continuous_vars
end
