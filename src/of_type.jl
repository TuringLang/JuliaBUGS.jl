abstract type OfType end

struct OfArray{T,N} <: OfType
    element_type::Type
    dims::NTuple{N,Int}
end

struct OfReal <: OfType
    lower::Union{Nothing,Real}
    upper::Union{Nothing,Real}
end

struct OfTuple{T<:Tuple} <: OfType
    types::T
end

struct OfNamedTuple{names,T<:Tuple} <: OfType
    types::T
end

function of(::Type{Array}, dims::Int...)
    return OfArray{Any,length(dims)}(Any, dims)
end

function of(::Type{Array}, T::Union{Type,OfType}, dims::Int...)
    element_type = T isa OfType ? julia_type(T) : T
    return OfArray{element_type,length(dims)}(element_type, dims)
end

function of(::Type{Real})
    return OfReal(nothing, nothing)
end

function of(::Type{Real}, lower::Real, upper::Real)
    return OfReal(lower, upper)
end

function of(t::Tuple)
    of_types = map(of, t)
    return OfTuple(of_types)
end

function of(nt::NamedTuple{names}) where {names}
    of_types = map(of, values(nt))
    return OfNamedTuple{names,typeof(of_types)}(of_types)
end

function of(x::OfType)
    return x
end

function julia_type(::OfArray{T,N}) where {T,N}
    return Array{T,N}
end

function julia_type(::OfReal)
    return Float64
end

function julia_type(oft::OfTuple)
    return Tuple{map(julia_type, oft.types)...}
end

function julia_type(oft::OfNamedTuple{names}) where {names}
    return NamedTuple{names,Tuple{map(julia_type, oft.types)...}}
end

Base.rand(ofa::OfArray{T,N}) where {T,N} = rand(T, ofa.dims...)

function Base.rand(ofr::OfReal)
    val = rand()
    if !isnothing(ofr.lower) && !isnothing(ofr.upper)
        return ofr.lower + val * (ofr.upper - ofr.lower)
    elseif !isnothing(ofr.lower)
        return ofr.lower + val
    elseif !isnothing(ofr.upper)
        return ofr.upper * val
    else
        return val
    end
end

function Base.rand(oft::OfTuple)
    return map(rand, oft.types)
end

function Base.rand(oft::OfNamedTuple{names}) where {names}
    values = map(rand, oft.types)
    return NamedTuple{names}(values)
end

Base.zero(ofa::OfArray{T,N}) where {T,N} = zeros(T, ofa.dims...)

function Base.zero(ofr::OfReal)
    if !isnothing(ofr.lower) && ofr.lower > 0
        return ofr.lower
    elseif !isnothing(ofr.upper) && ofr.upper < 0
        return ofr.upper
    else
        return 0.0
    end
end

function Base.zero(oft::OfTuple)
    return map(zero, oft.types)
end

function Base.zero(oft::OfNamedTuple{names}) where {names}
    values = map(zero, oft.types)
    return NamedTuple{names}(values)
end

(ofa::OfArray)() = zero(ofa)
(ofr::OfReal)() = zero(ofr)
(oft::OfTuple)() = zero(oft)
(ofnt::OfNamedTuple)() = zero(ofnt)

Base.convert(::Type{Type}, of_type::OfType) = julia_type(of_type)

function Base.show(io::IO, ofa::OfArray{T,N}) where {T,N}
    if T === Any
        print(io, "of(Array, ", join(ofa.dims, ", "), ")")
    else
        print(io, "of(Array, ", T, ", ", join(ofa.dims, ", "), ")")
    end
end

function Base.show(io::IO, ofr::OfReal)
    if isnothing(ofr.lower) && isnothing(ofr.upper)
        print(io, "of(Real)")
    else
        print(
            io,
            "of(Real, ",
            something(ofr.lower, "-∞"),
            ", ",
            something(ofr.upper, "∞"),
            ")",
        )
    end
end

function Base.show(io::IO, oft::OfTuple)
    print(io, "of((")
    for (i, t) in enumerate(oft.types)
        print(io, t)
        if i < length(oft.types)
            print(io, ", ")
        end
    end
    return print(io, "))")
end

function Base.show(io::IO, ofnt::OfNamedTuple{names}) where {names}
    print(io, "of((")
    for (i, (name, t)) in enumerate(zip(names, ofnt.types))
        print(io, name, "=", t)
        if i < length(names)
            print(io, ", ")
        end
    end
    return print(io, "))")
end