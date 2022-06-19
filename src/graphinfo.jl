using AbstractPPL
import Base.getindex
using SparseArrays
using Setfield
using Setfield: PropertyLens, get
using DensityInterface
using Random

"""
    GraphInfo

Record the state of the model as a struct of NamedTuples, all
sharing the same key values, namely, those of the model parameters.
`value` should store the initial/current value of the parameters.
`input` stores a tuple of inputs for a given node. `eval` are the
anonymous functions associated with each node. These might typically
be either deterministic values or some distribution, but could an 
arbitrary julia program. `kind` is a tuple of symbols indicating
whether the node is a logical or stochastic node. Additionally, the 
adjacency matrix and topologically ordered vertex list and stored.

GraphInfo is instantiated using the `Model` constctor. 
"""

struct GraphInfo{Tnames, Tinput, Tvalue, Teval, Tkind} <: AbstractModelTrace
    input::NamedTuple{Tnames, Tinput}
    value::NamedTuple{Tnames, Tvalue}
    eval::NamedTuple{Tnames, Teval}
    kind::NamedTuple{Tnames, Tkind}
    A::SparseMatrixCSC
    sorted_vertices::Vector{Symbol}
end

"""
    Model(;kwargs...)

`Model` type constructor that takes in named arguments for 
nodes and returns a `Model`. Nodes are pairs of variable names
and tuples containing default value, an eval function 
and node type. The inputs of each node are inferred from 
their anonymous functions. The returned object has a type 
GraphInfo{(sorted_vertices...)}.

# Examples
```jl-doctest
julia> using AbstractPPL

julia> Model(
               s2 = (0.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
               μ = (1.0, () -> 1.0, :Logical), 
               y = (0.0, (μ, s2) -> MvNormal(μ, sqrt(s2)), :Stochastic)
           )
Nodes: 
μ = (value = 1.0, input = (), eval = var"#6#9"(), kind = :Logical)
s2 = (value = 0.0, input = (), eval = var"#5#8"(), kind = :Stochastic)
y = (value = 0.0, input = (:μ, :s2), eval = var"#7#10"(), kind = :Stochastic)
```
"""

struct Model{Tnames, Tinput, Tvalue, Teval, Tkind} <: AbstractProbabilisticProgram
    g::GraphInfo{Tnames, Tinput, Tvalue, Teval, Tkind}
end

function Model(;kwargs...)
    for (i, node) in enumerate(values(kwargs))
        @assert node isa Tuple{Union{Array{Float64}, Float64}, Function, Symbol} "Check input order for node $(i) matches Tuple(value, function, kind)"
    end
    node_keys = keys(kwargs)
    vals = [getvals(NamedTuple(kwargs))...]
    vals[1] = Tuple([Ref(val) for val in vals[1]])
    args = [argnames(f) for f in vals[2]]
    A, sorted_inds = dag(NamedTuple{node_keys}(args))    
    sorted_vertices = node_keys[sorted_inds]
    model_inputs = NamedTuple{node_keys}.([Tuple.(args), vals...])
    sorted_model_inputs = [NamedTuple{sorted_vertices}(m) for m in model_inputs]
    Model(GraphInfo(sorted_model_inputs..., A, [sorted_vertices...]))
end

"""
    dag(inputs)

Function taking in a NamedTuple containing the inputs to each node 
and returns the implied adjacency matrix and topologically ordered 
vertex list.
"""
function dag(inputs)
    A = adjacency_matrix(inputs) 
    sorted_vertices = topological_sort_by_dfs(A)
    sorted_A = permute(A, collect(1:length(inputs)), sorted_vertices)
    sorted_A, sorted_vertices
end

"""
    getvals(nt::NamedTuple{T})

Takes in the arguments to Model(;kwargs...) as a NamedTuple and 
reorders into a tuple of tuples each containing either of value, 
input, eval and kind, as required by the GraphInfo type. 
"""
@generated function getvals(nt::NamedTuple{T}) where T
    values = [:(nt[$i][$j]) for i in 1:length(T), j in 1:3]
    m = [:($(values[:,i]...), ) for i in 1:3]
    return Expr(:tuple, m...)
end

"""
    argnames(f::Function)

Returns a Vector{Symbol} of the inputs to an anonymous function `f`.
"""
argnames(f::Function) = Base.method_argnames(first(methods(f)))[2:end]

"""
    adjacency_matrix(inputs)

For a NamedTuple{T} with vertices `T` paired with tuples of input nodes,
`adjacency_matrix` constructs the adjacency matrix using the order 
of variables given by `T`. 

# Examples
```jl-doctest
julia> inputs = (a = (), b = (), c = (:a, :b))
(a = (), b = (), c = (:a, :b))

julia> AbstractPPL.adjacency_matrix(inputs)
3×3 SparseMatrixCSC{Float64, Int64} with 2 stored entries:
  ⋅    ⋅    ⋅ 
  ⋅    ⋅    ⋅ 
 1.0  1.0   ⋅
``` 
"""
function adjacency_matrix(inputs::NamedTuple{nodes}) where {nodes}
    N = length(inputs)
    col_inds = NamedTuple{nodes}(ntuple(identity, N))
    A = spzeros(Bool, N, N)
    for (row, node) in enumerate(nodes)
        for input in inputs[node]
            if input ∉ nodes
                error("Parent node of $(input) not found in node set: $(nodes)")
            end
            col = col_inds[input]
            A[row, col] = true
        end
    end
    return A
end

function outneighbors(A::SparseMatrixCSC, u::T) where T <: Int
    #adapted from Graph.jl https://github.com/JuliaGraphs/Graphs.jl/blob/06669054ed470bcfe4b2ad90ed974f2e65c84bb6/src/interface.jl#L302
    inds, _ = findnz(A[:, u])
    inds
end

function topological_sort_by_dfs(A)
    # lifted from Graphs.jl https://github.com/JuliaGraphs/Graphs.jl/blob/06669054ed470bcfe4b2ad90ed974f2e65c84bb6/src/traversals/dfs.jl#L44
    # Depth first search implementation optimized from http://www.cs.nott.ac.uk/~psznza/G5BADS03/graphs2.pdf
    n_verts = size(A)[1]
    vcolor = zeros(UInt8, n_verts)
    verts = Vector{Int64}()
    for v in 1:n_verts
        vcolor[v] != 0 && continue
        S = Vector{Int64}([v])
        vcolor[v] = 1
        while !isempty(S)
            u = S[end]
            w = 0
            for n in outneighbors(A, u)
                if vcolor[n] == 1
                    error("The input graph contains at least one loop.") # TODO 0.7 should we use a different error?
                elseif vcolor[n] == 0
                    w = n
                    break
                end
            end
            if w != 0
                vcolor[w] = 1
                push!(S, w)
            else
                vcolor[u] = 2
                push!(verts, u)
                pop!(S)
            end
        end
    end
    return reverse(verts)
end

# getters and setters
"""
    Base.getindex(m::Model, vn::VarName{p})

Index a Model with a `VarName{p}` lens. Retrieves the `value``, `input`,
`eval` and `kind` for node `p`.

# Examples

```jl-doctest 
julia> using AbstractPPL

julia> m = Model( s2 = (0.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
                   μ = (1.0, () -> 1.0, :Logical), 
                   y = (0.0, (μ, s2) -> MvNormal(μ, sqrt(s2)), :Stochastic))
(s2 = Symbol[], μ = Symbol[], y = [:μ, :s2])
Nodes: 
μ = (value = 0.0, input = (), eval = var"#43#46"(), kind = :Stochastic)
s2 = (value = 1.0, input = (), eval = var"#44#47"(), kind = :Logical)
y = (value = 0.0, input = (:μ, :s2), eval = var"#45#48"(), kind = :Stochastic)


julia> m[@varname y]
(value = 0.0, input = (:μ, :s2), eval = var"#45#48"(), kind = :Stochastic)
```
"""
@generated function Base.getindex(g::GraphInfo, vn::VarName{p}) where {p}
    fns = fieldnames(GraphInfo)[1:4]
    name_lens = Setfield.PropertyLens{p}()
    field_lenses = [Setfield.PropertyLens{f}() for f in fns]
    values = [:(get(g, Setfield.compose($l, $name_lens, getlens(vn)))) for l in field_lenses]
    return :(NamedTuple{$(fns)}(($(values...),)))
end

function Base.getindex(m::Model, vn::VarName)
    return m.g[vn]
end

"""
    set_node_value!(m::Model, ind::VarName, value::T) where T

Change the value of the node. 

# Examples

```jl-doctest
julia> m = Model( s2 = (0.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
                         μ = (1.0, () -> 1.0, :Logical), 
                         y = (0.0, (μ, s2) -> Normal(μ, sqrt(s2)), :Stochastic))
Nodes: 
μ = (input = (), value = Base.RefValue{Float64}(1.0), eval = var"#38#41"(), kind = :Logical)
s2 = (input = (), value = Base.RefValue{Float64}(0.0), eval = var"#37#40"(), kind = :Stochastic)
y = (input = (:μ, :s2), value = Base.RefValue{Float64}(0.0), eval = var"#39#42"(), kind = :Stochastic)


julia> set_node_value!(m, @varname(s2), 1.0)
1.0

julia> get_node_value(m, @varname s2)
1.0
```
"""
function set_node_value!(m::Model, ind::VarName, value::T) where T
    @assert typeof(m[ind].value[]) == T
    m[ind].value[] = value
end

"""
    get_node_value(m::Model, ind::VarName)

Retrieve the value of a particular node, indexed by a VarName.

# Examples

julia> m = Model( s2 = (0.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
                         μ = (1.0, () -> 1.0, :Logical), 
                         y = (0.0, (μ, s2) -> MvNormal(μ, sqrt(s2)), :Stochastic))
Nodes: 
μ = (input = (), value = Base.RefValue{Float64}(1.0), eval = var"#44#47"(), kind = :Logical)
s2 = (input = (), value = Base.RefValue{Float64}(0.0), eval = var"#43#46"(), kind = :Stochastic)
y = (input = (:μ, :s2), value = Base.RefValue{Float64}(0.0), eval = var"#45#48"(), kind = :Stochastic)


julia> get_node_value(m, @varname s2)
0.0
"""

function get_node_value(m::Model, ind::VarName) 
    v = get(m[ind], @lens _.value)
    v[]
end

function get_node_value(m::Model, ind)
    values = Vector{Union{Float64, Array{Float64}}}()
    for i in ind
        push!(values, get_node_value(m, VarName{i}()))
    end
    values
end

"""
    get_node_ref_value(m::Model, ind::VarName)
    get_node_ref_value(m::Model, ind::NTuple{N, Symbol})

Return the mutable Ref value associated with a node or tuple 
of nodes.
"""
function get_node_ref_value(m::Model, ind::VarName) 
    get(m[ind], @lens _.value)
end

function get_node_ref_value(m::Model, ind)
    values = Vector{Union{Base.RefValue{Float64}, Base.RefValue{Vector{Float64}}}}()
    for i in ind
        push!(values, get_node_ref_value(m, VarName{i}()))
    end
    values
end

"""
    get_node_input(m::Model, ind::VarName)

Retrieve the inputs/parents of a node, as given by model DAG.
"""
get_node_input(m::Model, ind::VarName) = get(m[ind], @lens _.input)

"""
    get_node_input(m::Model, ind::VarName)

Retrieve the evaluation function for a node. 
"""
get_node_eval(m::Model, ind::VarName) = get(m[ind], @lens _.eval)

"""
    get_nodekind(m::Model, ind::VarName)

Retrieve the type of the node, i.e. stochastic or logical. 
"""
get_nodekind(m::Model, ind::VarName) = get(m[ind], @lens _.kind)

"""
    get_nodes(m::Model, kind::Symbol)
    
Retrieve the nodes of kind `kind`. 
"""
function get_nodes(m::AbstractPPL.GraphPPL.Model, kind::Symbol)
    if kind ∉ [:Logical, :Stochastic, :Observations]
        error("Node kind should be :Logical, :Stochastic or :Observations")
    end
    nodes = Vector{Symbol}()
    for vn in keys(m)
        if get_nodekind(m, vn) == kind
            push!(nodes, getsym(vn))
        end
    end
    Tuple(nodes)
end

"""
    get_dag(m::Model)

Returns the adjacency matrix of the model as a SparseArray.
"""
get_dag(m::Model) = get(m, @lens _.g.A)

"""
    get_sorted_vertices(m::Model)

Returns a `Vector{Symbol}` containing the sorted vertices 
of the DAG. 
"""
get_sorted_vertices(m::Model) =  get(m, @lens _.g.sorted_vertices)


"""
    get_model_values(m::Model)

Returns a Named Tuple of nodes and node values.
"""
function get_model_values(m::Model{T}) where T
    NamedTuple{T}(get_node_value(m, T))
end

"""
    get_model_ref_values(m::Model)

Returns a Named Tuple of nodes and node Ref values.
"""
function get_model_ref_values(m::Model{T}) where T
    NamedTuple{T}(get_node_ref_value(m, T))
end

"""
    set_model_values!(m::Model, values::NamedTuple)

Changes the values of the `Model` node values to those 
given by a Named Tuple of node symboles and new values. 
"""
function set_model_values!(m::Model{T}, values::NamedTuple{T}) where T
    for vn in keys(m)
        if get_nodekind(m, vn) != :Observations
            set_node_value!(m, vn, get(values, vn))
        end
    end
end

# iterators

function Base.iterate(m::Model, state=1)
    state > length(get_sorted_vertices(m)) ? nothing : (m[VarName{m.g.sorted_vertices[state]}()], state+1)
end

Base.eltype(m::Model) = NamedTuple{fieldnames(GraphInfo)[1:4]}
Base.IteratorEltype(m::Model) = Base.HasEltype()

Base.keys(m::Model) = (VarName{n}() for n in m.g.sorted_vertices)
Base.values(m::Model) = Base.Generator(identity, m)
Base.length(m::Model) = length(get_sorted_vertices(m))
Base.keytype(m::Model) = eltype(keys(m))
Base.valtype(m::Model) = eltype(m)

# show methods
function Base.show(io::IO, m::Model)
    print(io, "Nodes: \n")
    for node in get_sorted_vertices(m)
        print(io, "$node = ", m[VarName{node}()], "\n")
    end
end

"""
    rand!(rng::AbstractRNG, m::Model)

Draw random samples from the model and mutate the node values. 

# Examples

```jl-doctest
julia> import AbstractPPL.GraphPPL: Model, rand!
       using Distributions

julia> using Random; Random.seed!(1234)
TaskLocalRNG()

julia> m = Model(s2 = (0.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
                 μ = (1.0, () -> 1.0, :Logical), 
                 y = (0.0, (μ, s2) -> Normal(μ, sqrt(s2)), :Stochastic))
Nodes: 
μ = (input = (), value = Base.RefValue{Float64}(1.0), eval = var"#6#9"(), kind = :Logical)
s2 = (input = (), value = Base.RefValue{Float64}(0.0), eval = var"#5#8"(), kind = :Stochastic)
y = (input = (:μ, :s2), value = Base.RefValue{Float64}(0.0), eval = var"#7#10"(), kind = :Stochastic)


julia> rand!(m)
Nodes: 
μ = (input = (), value = Base.RefValue{Float64}(1.0), eval = var"#6#9"(), kind = :Logical)
s2 = (input = (), value = Base.RefValue{Float64}(2.7478186975593846), eval = var"#5#8"(), kind = :Stochastic)
y = (input = (:μ, :s2), value = Base.RefValue{Float64}(0.3044653509044275), eval = var"#7#10"(), kind = :Stochastic)
```
"""
function Random.rand!(rng::AbstractRNG, m::AbstractPPL.GraphPPL.Model{T}) where T
    for vn in keys(m)
        input, _, f, kind = m[vn]
        input_values = get_node_value(m, input)
        if kind == :Stochastic || kind == :Observations
            set_node_value!(m, vn, rand(rng, f(input_values...)))
        else
            set_node_value!(m, vn, f(input_values...))
        end
    end
    m
end

function Random.rand!(m::AbstractPPL.GraphPPL.Model{T}) where T
    rand!(Random.GLOBAL_RNG, m)
end

"""
    rand!(rng::AbstractRNG, m::Model)

Draw random samples from the model and mutate the node values. 

# Examples

```jl-doctest
julia> using Random; Random.seed!(1234)

julia> import AbstractPPL.GraphPPL: Model, rand
[ Info: Precompiling AbstractPPL [7a57a42e-76ec-4ea3-a279-07e840d6d9cf]

julia> using Distributions

julia> m = Model(s2 = (1.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
                 μ = (0.0, () -> 1.0, :Logical), 
                 y = (0.0, (μ, s2) -> Normal(μ, sqrt(s2)), :Stochastic))
Nodes: 
μ = (input = (), value = Base.RefValue{Float64}(1.0), eval = var"#6#9"(), kind = :Logical)
s2 = (input = (), value = Base.RefValue{Float64}(0.0), eval = var"#5#8"(), kind = :Stochastic)
y = (input = (:μ, :s2), value = Base.RefValue{Float64}(0.0), eval = var"#7#10"(), kind = :Stochastic)

julia> rand(m)
(μ = 1.0, s2 = 1.0907695400401212, y = 0.05821954440386368)
```
"""
function Random.rand(rng::AbstractRNG, sm::Random.SamplerTrivial{Model{Tnames, Tinput, Tvalue, Teval, Tkind}}) where {Tnames, Tinput, Tvalue, Teval, Tkind}
    m = deepcopy(sm[])
    get_model_values(rand!(rng, m))
end

"""
    logdensityof(m::Model)

Evaluate the log-densinty of the model. 

# Examples

```jl-doctest
julia> using Random; Random.seed!(1234)
MersenneTwister(1234)

julia> import AbstractPPL.GraphPPL: Model, logdensityof
[ Info: Precompiling AbstractPPL [7a57a42e-76ec-4ea3-a279-07e840d6d9cf]

julia> using Distributions

julia> m = Model(s2 = (1.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
                 μ = (0.0, () -> 1.0, :Logical), 
                 y = (0.0, (μ, s2) -> Normal(μ, sqrt(s2)), :Stochastic))
Nodes: 
μ = (input = (), value = Base.RefValue{Float64}(1.0), eval = var"#6#9"(), kind = :Logical)
s2 = (input = (), value = Base.RefValue{Float64}(0.0), eval = var"#5#8"(), kind = :Stochastic)
y = (input = (:μ, :s2), value = Base.RefValue{Float64}(0.0), eval = var"#7#10"(), kind = :Stochastic)

julia> logdensityof(m)
-1.721713955868453
```
"""
function DensityInterface.logdensityof(m::AbstractPPL.GraphPPL.Model)
    logdensityof(m, get_model_values(m))
end

"""
    logdensityof(m::Model{T}, v::NamedTuple{T})

Evaluate the log-densinty of the model. 

# Examples

```jl-doctest
julia> using Random; Random.seed!(1234)
MersenneTwister(1234)

julia> import AbstractPPL.GraphPPL: Model, logdensityof, get_model_values
[ Info: Precompiling AbstractPPL [7a57a42e-76ec-4ea3-a279-07e840d6d9cf]

julia> using Distributions

julia> m = Model(s2 = (1.0, () -> InverseGamma(2.0,3.0), :Stochastic), 
                 μ = (0.0, () -> 1.0, :Logical), 
                 y = (0.0, (μ, s2) -> Normal(μ, sqrt(s2)), :Stochastic))
Nodes: 
μ = (input = (), value = Base.RefValue{Float64}(1.0), eval = var"#6#9"(), kind = :Logical)
s2 = (input = (), value = Base.RefValue{Float64}(0.0), eval = var"#5#8"(), kind = :Stochastic)
y = (input = (:μ, :s2), value = Base.RefValue{Float64}(0.0), eval = var"#7#10"(), kind = :Stochastic)

julia> logdensityof(m, get_model_values(m))
-1.721713955868453
"""
function DensityInterface.logdensityof(m::AbstractPPL.GraphPPL.Model{T}, v::NamedTuple{T, V}) where {T, V}
    lp = 0.0
    for vn in keys(m)
        input, _, f, kind = m[vn]
        input_values = get_node_value(m, input)
        value = get(v, vn)
        if kind == :Stochastic || kind == :Observations
            # check whether this is a constrained variable #TODO use bijectors.jl
            lp += logdensityof(f(input_values...), value)
        end
    end
    lp
end