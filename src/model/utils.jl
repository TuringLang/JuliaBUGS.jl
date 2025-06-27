# TODO: can't remove even with the `possible` fix in DynamicPPL, still seems to have eltype inference issue causing AD errors
# Resolves: setindex!!([1 2; 3 4], [2 3; 4 5], 1:2, 1:2) # returns 2×2 Matrix{Any}
# Alternatively, can overload BangBang.possible(
#     ::typeof(BangBang._setindex!), ::C, ::T, ::Vararg
# )
# to allow mutation, but the current solution seems create less possible problems, albeit less efficient.

# Wrapper to avoid piracy
struct SafeArray{T<:AbstractArray}
    data::T
end

# Safe mutation with concrete eltype
function BangBang.NoBang._setindex(sa::SafeArray, v::AbstractArray, I...)
    xs = sa.data
    T = promote_type(eltype(xs), eltype(v))
    ys = similar(xs, T)
    if eltype(xs) !== Union{}
        copy!(ys, xs)
    end
    ys[I...] = v
    return SafeArray(ys)
end

BangBang.possible(::typeof(BangBang._setindex!), sa::SafeArray, v::AbstractArray, I...) = true

# Robust setindex!! for NamedTuple
function BangBang.setindex!!(nt::NamedTuple, val, vn::VarName{sym}) where {sym}
    optic = BangBang.prefermutation(
        AbstractPPL.getoptic(vn) ∘ Accessors.PropertyLens{sym}()
    )
    Accessors.set(nt, optic, val)
end

"""
    reconstruct([f, ]dist, val)

Reconstruct `val` so that it's compatible with `dist`.

If `f` is also provided, the reconstruct value will be
such that `f(reconstruct_val)` is compatible with `dist`.
"""
reconstruct(f, dist, val) = reconstruct(dist, val)

# No-op versions.
reconstruct(::UnivariateDistribution, val::Real) = val
reconstruct(::MultivariateDistribution, val::AbstractVector{<:Real}) = copy(val)
reconstruct(::MatrixDistribution, val::AbstractMatrix{<:Real}) = copy(val)
function reconstruct(
    ::Distribution{ArrayLikeVariate{N}}, val::AbstractArray{<:Real,N}
) where {N}
    return copy(val)
end

function reconstruct(dist::LKJCholesky, val::AbstractVector{<:Real})
    return reconstruct(dist, Matrix(reshape(val, size(dist))))
end
reconstruct(dist::LKJCholesky, val::AbstractMatrix{<:Real}) = Cholesky(val, dist.uplo, 0)
reconstruct(::LKJCholesky, val::Cholesky) = val

# NOTE: Necessary to handle product distributions of `Dirichlet` and similar.
function reconstruct(
    ::Bijectors.Inverse{<:Bijectors.SimplexBijector}, dist, val::AbstractVector
)
    (d, ns...) = size(dist)
    return reshape(val, d - 1, ns...)
end
function reconstruct(
    ::Bijectors.Inverse{Bijectors.VecCorrBijector}, ::LKJ, val::AbstractVector
)
    return copy(val)
end
function reconstruct(
    ::Bijectors.Inverse{Bijectors.VecCholeskyBijector}, ::LKJCholesky, val::AbstractVector
)
    return copy(val)
end
function reconstruct(
    ::Bijectors.Inverse{Bijectors.PDVecBijector}, ::MatrixDistribution, val::AbstractVector
)
    return copy(val)
end

reconstruct(d::Distribution, val::AbstractVector) = reconstruct(size(d), val)
reconstruct(::Tuple{}, val::AbstractVector) = val[1]
reconstruct(s::NTuple{1}, val::AbstractVector) = copy(val)
reconstruct(s::NTuple{2}, val::AbstractVector) = reshape(copy(val), s)

#######################
# Evaluation Environment Utilities
#######################

"""
    get_mutable_symbols(data) -> Set{Symbol}

Identify all symbols in the evaluation environment that may be mutated during model evaluation.

When called with a model, extracts the graph evaluation data first.

This includes:
- Model parameters (stochastic nodes that are not observations)
- Deterministic (logical) nodes

Does NOT include:
- Observed data (remains constant during sampling)
- Constants defined outside the model

# Examples
```julia
model_def = @bugs begin
    x ~ Normal(0, 1)  # parameter - mutable
    y = x^2           # deterministic - mutable
    z ~ Normal(y, 1)  # observed data - immutable
end
model = compile(model_def, (; z = 1.5))
mutable_syms = get_mutable_symbols(model.graph_evaluation_data)
# Returns: Set([:x, :y])
```
"""
function get_mutable_symbols(data)
    # If data has graph_evaluation_data field, extract it
    graph_data =
        hasproperty(data, :graph_evaluation_data) ? data.graph_evaluation_data : data

    mutable_syms = Set{Symbol}()

    # Add symbols from model parameters (stochastic, non-observed nodes)
    for vn in graph_data.sorted_parameters
        push!(mutable_syms, AbstractPPL.getsym(vn))
    end

    # Add symbols from deterministic (logical) nodes
    for (i, vn) in enumerate(graph_data.sorted_nodes)
        if !graph_data.is_stochastic_vals[i]
            push!(mutable_syms, AbstractPPL.getsym(vn))
        end
    end

    return mutable_syms
end

"""
    smart_copy_evaluation_env(env::NamedTuple, mutable_syms::Set{Symbol}) -> NamedTuple

Create a copy of the evaluation environment where only mutable parts are deep copied.

Immutable parts (like observed data) are shared between the original and copy,
avoiding expensive memory allocations and copies.

# Arguments
- `env`: The evaluation environment to copy
- `mutable_syms`: Set of symbols that need to be deep copied

# Returns
A new NamedTuple with:
- Deep copies of mutable fields
- Shared references to immutable fields

# Examples
```julia
env = (x = [1.0, 2.0], data = rand(10000), y = 3.0)
mutable_syms = Set([:x, :y])
new_env = smart_copy_evaluation_env(env, mutable_syms)
# new_env.x is a copy, new_env.data is the same object, new_env.y is a copy
```
"""
function smart_copy_evaluation_env(env::NamedTuple, mutable_syms::Set{Symbol})
    # Get all keys from the environment
    env_keys = keys(env)

    # Determine which keys to copy vs share
    keys_to_copy = intersect(env_keys, mutable_syms)
    keys_to_share = setdiff(env_keys, mutable_syms)

    # Build new environment
    new_values = Dict{Symbol,Any}()

    # Deep copy mutable parts
    for k in keys_to_copy
        new_values[k] = deepcopy(env[k])
    end

    # Share immutable parts (no copy)
    for k in keys_to_share
        new_values[k] = env[k]
    end

    # Create and return new NamedTuple
    return NamedTuple(new_values)
end
