using MetaGraphsNext
using Graphs
using Distributions

"""
    BayesianNetwork

A structure representing a Bayesian Network.
"""
struct BayesianNetwork{V,T,F}
    graph::SimpleDiGraph{T}
    "names of the variables in the network"
    names::Vector{V}
    "mapping from variable names to ids"
    names_to_ids::Dict{V,T}
    "values of each variable in the network"
    values::Dict{V,Any} # TODO: make it a NamedTuple for better performance in the future
    "distributions of the stochastic variables"
    distributions::Vector{Distribution}
    "deterministic functions of the deterministic variables"
    deterministic_functions::Vector{F}
    "ids of the stochastic variables"
    stochastic_ids::Vector{T}
    "ids of the deterministic variables"
    deterministic_ids::Vector{T}
    is_stochastic::BitVector
    is_observed::BitVector
    node_types::Vector{Symbol}            # e.g. :discrete or :continuous
end

function BayesianNetwork{V}() where {V}
    return BayesianNetwork(
        SimpleDiGraph{Int}(), # by default, vertex ids are integers
        V[],
        Dict{V,Int}(),
        Dict{V,Any}(),
        Distribution[],
        Any[],
        Int[],
        Int[],
        BitVector(),
        BitVector(),
        Symbol[],
    )
end

"""
    translate_BUGSGraph_to_BayesianNetwork(g::MetaGraph; init=Dict{Symbol,Any}())

Translates a BUGSGraph (with node metadata stored in NodeInfo) into a BayesianNetwork.
For stochastic nodes, if the node function is a function and its expression is a call to dnorm,
the parameters are extracted (using `eval`) so that, for example, a node defined as
`b ~ dnorm(1, 1)` yields `Normal(1, 1)`.
For deterministic nodes, an anonymous function is constructed from the stored expression and node arguments.
A cache ensures that identical expressions yield the same function object.

The optional keyword argument `init` is a dictionary mapping variable symbols (e.g. :a) to their initial values.
If not provided, it defaults to an empty dictionary.
"""
function translate_BUGSGraph_to_BayesianNetwork(g::MetaGraph; init=Dict{Symbol,Any}())
    # Retrieve variable labels (stored as VarNames) from g.
    varnames = collect(labels(g))
    n = length(varnames)
    original_graph = g.graph

    # Preallocate arrays/dictionaries.
    names = Vector{Symbol}(undef, n)
    names_to_ids = Dict{Symbol,Int}()
    values = Dict{Symbol,Any}()
    distributions = Vector{Distribution}(undef, n)
    deterministic_fns = Vector{Any}(undef, n)
    stochastic_ids = Int[]
    deterministic_ids = Int[]
    is_stochastic = falses(n)
    is_observed = falses(n)
    node_types = Vector{Symbol}(undef, n)

    # Cache for deterministic function expressions.
    cache = Dict{String,Any}()

    for (i, varname) in enumerate(varnames)
        let symbol_name = Symbol(varname) #dont need let
            if !haskey(g, varname)
                continue
            end
            local nodeinfo = g[varname] # dont need local

            names[i] = symbol_name
            names_to_ids[symbol_name] = i
            values[symbol_name] = get(init, symbol_name, nothing)

            is_stochastic[i] = nodeinfo.is_stochastic
            is_observed[i] = nodeinfo.is_observed

            if nodeinfo.is_stochastic
                if nodeinfo.node_function isa Distribution
                    distributions[i] = nodeinfo.node_function
                    println("nodeinfo.node_function is a Distribution")
                    println(distributions[i])
                elseif nodeinfo.node_function isa Function
                    if nodeinfo.node_function_expr.head == :call &&
                        nodeinfo.node_function_expr.args[1] == :dnorm
                        # Evaluate the literal parameters.
                        μ = eval(nodeinfo.node_function_expr.args[2])
                        σ = eval(nodeinfo.node_function_expr.args[3])

                        distributions[i] = Normal(μ, σ)
                    else
                        try
                            distributions[i] = nodeinfo.node_function()
                            if !(distributions[i] isa Distribution)
                                throw("Returned value is not a Distribution")
                            end
                        catch
                            distributions[i] = Normal()
                        end
                    end
                else
                    distributions[i] = Normal()
                end
                deterministic_fns[i] = nothing
                push!(stochastic_ids, i)
                node_types[i] = :stochastic
            else
                distributions[i] = Normal()  # Placeholder for deterministic nodes.
                if length(nodeinfo.node_function_expr.args) >= 2
                    local body_expr = nodeinfo.node_function_expr.args[2]
                else
                    error("Deterministic node expression is malformed.")
                end
                # Construct an anonymous function, e.g., (a, b) -> a + b, using node_args.
                local fn_expr = Expr(:->, Expr(:tuple, nodeinfo.node_args...), body_expr)
                local s = string(fn_expr)
                if haskey(cache, s)
                    deterministic_fns[i] = cache[s]
                else
                    deterministic_fns[i] = eval(fn_expr)
                    cache[s] = deterministic_fns[i]
                end
                push!(deterministic_ids, i)
                node_types[i] = :deterministic
            end
        end
    end

    local bn = BayesianNetwork(
        SimpleDiGraph{Int}(n),
        names,
        names_to_ids,
        values,
        distributions,
        deterministic_fns,
        stochastic_ids,
        deterministic_ids,
        is_stochastic,
        is_observed,
        node_types,
    )

    # Add edges using the BayesianNetwork's mapping.
    for e in edges(original_graph)
        let src_name = bn.names[e.src]
            let dst_name = bn.names[e.dst]
                add_edge!(bn, src_name, dst_name)
            end
        end
    end

    return bn
end

"""
    add_stochastic_vertex!(bn::BayesianNetwork{V,T}, name::V, dist::Any, node_type::Symbol; is_observed::Bool=false) where {V,T}

Add a stochastic vertex with name `name`, a distribution object/function `dist`,
and a declared node_type (`:discrete` or `:continuous`).
"""
function add_stochastic_vertex!(
    bn::BayesianNetwork{V,T},
    name::V,
    dist::Any,
    is_observed::Bool=false,
    node_type::Symbol=:continuous,
)::T where {V,T}
    Graphs.add_vertex!(bn.graph) || return 0
    id = nv(bn.graph)
    push!(bn.distributions, dist)
    push!(bn.is_stochastic, true)
    push!(bn.is_observed, is_observed)
    push!(bn.names, name)
    bn.names_to_ids[name] = id
    push!(bn.stochastic_ids, id)
    push!(bn.node_types, node_type)
    return id
end

"""
    add_deterministic_vertex!(bn::BayesianNetwork{V,T}, name::V, f::F) where {T,V,F}

Add a deterministic vertex.
"""
function add_deterministic_vertex!(bn::BayesianNetwork{V,T}, name::V, f::F)::T where {T,V,F}
    Graphs.add_vertex!(bn.graph) || return 0
    id = nv(bn.graph)
    push!(bn.deterministic_functions, f)
    push!(bn.is_stochastic, false)
    push!(bn.is_observed, false)
    push!(bn.names, name)
    bn.names_to_ids[name] = id
    push!(bn.deterministic_ids, id)
    push!(bn.node_types, :deterministic)
    return id
end

"""
    add_edge!(bn::BayesianNetwork{V,T}, from::V, to::V) where {T,V}

Add a directed edge from `from` -> `to`.
"""
function add_edge!(bn::BayesianNetwork{V,T}, from::V, to::V)::Bool where {T,V}
    from_id = bn.names_to_ids[from]
    to_id = bn.names_to_ids[to]
    return Graphs.add_edge!(bn.graph, from_id, to_id)
end
