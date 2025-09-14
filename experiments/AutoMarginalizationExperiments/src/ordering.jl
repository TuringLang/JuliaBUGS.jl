using JuliaBUGS
const JModel = JuliaBUGS.Model
using AbstractPPL

"""
    build_interleaved_order(model)

For models with paired latent/observations like HMMs or mixture models where
names contain `z[i]` and `y[i]`, return an order that keeps non (z,y) nodes first
and then interleaves `z[i], y[i]` by ascending i. Falls back to `sorted_nodes`
when names are not present.
"""
function build_interleaved_order(model)
    gd = model.graph_evaluation_data
    z_idxs = Dict{Int,Int}()
    y_idxs = Dict{Int,Int}()
    other = Int[]
    for (j, vn) in enumerate(gd.sorted_nodes)
        s = string(vn)
        if startswith(s, "z[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0; z_idxs[i] = j; else; push!(other, j); end
        elseif startswith(s, "y[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0; y_idxs[i] = j; else; push!(other, j); end
        else
            push!(other, j)
        end
    end
    order = copy(other)
    if !isempty(z_idxs)
        for i in sort(collect(keys(z_idxs)))
            zi = z_idxs[i]
            push!(order, zi)
            yi = get(y_idxs, i, 0)
            if yi != 0; push!(order, yi); end
        end
    end
    return order
end

"""
    prepare_minimal_cache_keys(model, order)

Wrapper around `JuliaBUGS.Model._precompute_minimal_cache_keys` returning a Dict.
"""
function prepare_minimal_cache_keys(model, order::AbstractVector{<:Integer})
    return JModel._precompute_minimal_cache_keys(model, collect(order))
end
