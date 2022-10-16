using DynamicPPL
using MacroTools
using Distributions

# TODO: because all the loops are unrolled, for large models, no vectorization means slow speed in Turing
# the mitigation is to use topological order obtained with BUGSGraph and directly translate the BUGS code pre-unrolling

"""
    toTuring(g::SymbolicPPL.Graph)

Convert a `SymbolicPPL.Graph` to a `DynamicPPL.Model`.
"""
function toTuring(g::BUGSGraph)
    turing_expr = DynamicPPL.model(@__MODULE__, LineNumberNode(@__LINE__, @__FILE__), inputtoTuring(g), false)
    eval(turing_expr)
    return bugsturing
end

"""
    inputtoTuring(g)

Return the input to `DynamicPPL.@model`.
"""
function inputtoTuring(g::BUGSGraph)
    expr = []
    args = Dict()
    for n in getsortednodes(g)
        funccall = MacroTools.unresolve(deepcopy(g.nodefunc[n].args[2]))
        if isa(funccall, Expr)
            funccall.args[1] = Expr(:., :SymbolicPPL, QuoteNode(funccall.args[1]))
            push!(expr, Expr(:call, :(~), g.reverse_nodeenum[n], funccall))
        elseif isa(funccall, Distributions.Distribution)
            funccall = Expr(:call, nameof(typeof(funccall)), Distributions.params(funccall)...)
            push!(expr, Expr(:call, :(~), g.reverse_nodeenum[n], funccall))
        end
    end
    args = [Expr(:kw, g.reverse_nodeenum[a[1]], a[2]) for a in g.observed_values]
    ex = Expr(:function, Expr(:call, :bugsturing, Expr(:parameters, args...)), Expr(:block, expr...))
    return ex
end