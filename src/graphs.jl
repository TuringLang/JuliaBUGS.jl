abstract type Effect end
abstract type Pure <: Effect end
abstract type MutateGraph <: Effect end

abstract type FunctionType end
# TODO: probably lens and args should be stored in GraphNode
struct LogicalFunction{TE<:Effect} <: FunctionType
    l::Lens
    f::Function
    args::Vector{Var}
end

struct StochasticFunction{TE<:Effect} <: FunctionType
    l::Lens
    f::Function
    args::Vector{Var}
end

function (f::LogicalFunction{<:Pure})(trace, args::Vector{Float64})
    trace[f.l] = f.f(args)
end

function (f::StochasticFunction{<:Pure})(trace, args::Vector{Float64})
    value, logp = f.f(args)
    trace.values[f.l] = value
    trace.logp += logp
end


# TODO: work out a way to translate VarName back to Var, not necessary useful. but varname should be similar to Var

struct GraphNode
    label::Var
    vn::VarName
    args::Vector{Var}
    effects
end

# kinds of effects: 1. trace.values 2. trace.logp 3. graph itself 4. other

# Separate node function and node effect
# node effect can be abstracted out like Cassettes.jl, i.e., a prehook and a posthook

using AbstractPPL
vn = @varname(x[1, 2])
typeof(vn) # VarName{:x, Setfield.IndexLens{Tuple{Int64, Int64}}}
lens = getlens(vn) # (@lens _[1, 2])
lens.indices # index lens

vn2 = @varname(x[1:2, :])
getlens(vn2) |> typeof
getlens(vn2).indices

vn2_c = AbstractPPL.concretize(vn2, rand(3, 4)) # VarName{:x, Setfield.IndexLens{Tuple{UnitRange{Int64}, Colon}}}
getlens(vn2_c).indices

a = [1.0, 2, 3]

b = [1, 2, 3]
b[a[1]]

# compile to Turing:
# if we only consider simple cases where there's no loop between elements in the same argument in the same loop, then translation is simple

# try first pass without run loops: precondition and matching

# try Cassettes
