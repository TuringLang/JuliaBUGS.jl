
struct VertexInfo
    variable_name::Symbol
    sorted_inputs::Tuple
    is_data::Bool
    data::Union{Missing,Real}
    f_expr::Expr
    f::Function
end

function to_metadigraph(pre_graph::Dict)
    g = MetaGraph(DiGraph(), Label = Symbol, VertexData = VertexInfo)
    
    for k in keys(pre_graph)
        vi = VertexInfo(
            k,
            Tuple(pre_graph[k][2].args[1].args), 
            pre_graph[k][3], 
            pre_graph[k][1],
            pre_graph[k][2],
            eval(pre_graph[k][2])
        )
        g[k] = vi
    end

    for k in keys(pre_graph)
        for p in g[k].sorted_inputs
            add_edge!(g, p, k, nothing) || error("Edge addition failed for $p -> $k.")
        end
    end

    return g
end

function process_initializations(inits::NamedTuple)
    initializations = Dict{Symbol, Real}()
    for (k, v) in pairs(inits)
        if v isa Array
            for i in CartesianIndices(v)
                ismissing(v[i]) && continue
                s = bugs_to_julia("$k") * "$(collect(Tuple(i)))"
                n = tosymbol(tosymbolic(Meta.parse(s)))
                initializations[n] = v[i]
            end
        else
            occursin("[", string(k)) && 
                error("Initializations of single elements of arrays not supported, initialize the whole array instead.")
            initializations[k] = v
        end
    end
    return initializations
end

"""
    getdistribution(g, node, value)

Return a Distribution.jl distribution.
"""
function getdistribution(g::MetaDiGraph, node::Symbol, value::Dict{Symbol, Real}, delta::Dict{Symbol, <:Real}=Dict{Symbol, Float64}())::Distributions.Distribution
    args = []
    for p in g[node].sorted_inputs
        if p in keys(delta)
            push!(args, delta[p])
        else
            push!(args, value[p])
        end
    end
    return (g[node].f)(args...)
end

function Base.show(io::IO, vinfo::VertexInfo)
    vinfo = deepcopy(vinfo)
    f_expr = vinfo.f_expr
    arguments = f_expr.args[1].args
    _io = IOBuffer();
    for i in 1:length(arguments)
        print(_io, arguments[i])
        if i < length(arguments)
            print(_io, ", ")
        end
    end
    d_expr = f_expr.args[2].args[1]

    function numify(expr)
        MacroTools.prewalk(expr) do sub_expr
            if Meta.isexpr(sub_expr, :call)
                for (i, arg) in enumerate(sub_expr.args[2:end])
                    if arg isa Symbol
                        sub_expr.args[1+i] = tosymbolic(arg)
                    elseif arg isa Expr
                        sub_expr.args[1+i] = numify(arg) 
                    end
                end 
            end
            return sub_expr
        end
    end

    d_expr = numify(d_expr)
    d_expr = eval(d_expr)
    
    println(io, "Variable Name: " * string(vinfo.variable_name))
    println(io, "Variable Type: " * (vinfo.is_data ? "Observation" : "Assumption"))
    vinfo.is_data && println(io, "Data: " * string(vinfo.data))
    println(io, "Parent Nodes: " * String(take!(_io)))
    print(io, "Node Function: ")
    Base.show(io, d_expr)
end
