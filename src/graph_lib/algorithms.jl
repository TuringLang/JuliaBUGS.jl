# TODO: abstract this using colors
# function stochastic_neighbors(
#     g::BUGSGraph,
#     v::VarName,
#     f::Union{
#         typeof(MetaGraphsNext.inneighbor_labels),typeof(MetaGraphsNext.outneighbor_labels)
#     },
# )
#     stochastic_neighbors_vec = VarName[]
#     logical_en_route = VarName[] # logical variables
#     for u in f(g, v)
#         if g[u] isa ConcreteNodeInfo
#             if g[u].node_type == Stochastic
#                 push!(stochastic_neighbors_vec, u)
#             else
#                 push!(logical_en_route, u)
#                 ns = stochastic_neighbors(g, u, f)
#                 for n in ns
#                     push!(stochastic_neighbors_vec, n)
#                 end
#             end
#         else
#             # auxiliary nodes are not counted as logical nodes
#             ns = stochastic_neighbors(g, u, f)
#             for n in ns
#                 push!(stochastic_neighbors_vec, n)
#             end
#         end
#     end
#     return [stochastic_neighbors_vec..., logical_en_route...]
# end
