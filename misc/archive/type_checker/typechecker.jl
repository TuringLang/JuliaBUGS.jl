abstract type LinkedList{T} end
struct Nil{T} <: LinkedList{T} end
struct Cons{T} <: LinkedList{T}
    head::T
    tail::LinkedList{T}
end
LinkedList{T}(cs::T...) where {T} = foldr(Cons, cs; init=Nil{T}())
LinkedList(cs::T...) where {T} = LinkedList{T}(cs...)
Base.foldr(op, ::Nil; init) = init
Base.foldr(op, l::Cons; init) = op(l.head, foldr(op, l.tail; init))
function Base.map(f, l::LinkedList{T}) where {T}
    return foldr((x, acc) -> Cons(f(x), acc), l; init=Nil{T}())
end
pushfirst!!(l::LinkedList{T}, x::T) where {T} = Cons(x, l)
pushfirst!!(l::LinkedList, xs...) = foldr(Cons, xs; init=l)
pop(l::Cons) = l.head, l.tail
function Base.collect(l::LinkedList{T}) where {T}
    return reverse!(foldr((x, acc) -> push!(acc, x), l; init=T[]))
end

Base.IteratorSize() = Base.SizeUnknown()
Base.IteratorEltype() = Base.HasEltype()
Base.eltype(::Type{LinkedList{T}}) where {T} = T
Base.iterate(l::LinkedList) = iterate(l, l)
Base.iterate(l::LinkedList, state::Nil) = nothing
Base.iterate(l::LinkedList, state::Cons) = state.head, state.tail

Base.show(io::IO, l::LinkedList) = print(io, "LinkedList(", join(l, ", "), ")")

## TYPES ###############
const ArgsTuple{T} = Tuple{Vararg{T}}

abstract type BugsType end
struct TypeName <: BugsType
    name::Symbol
end

abstract type BugsPrimType <: BugsType end
struct BugsVoid <: BugsPrimType end
struct Bugsℤ <: BugsPrimType end
struct Bugsℝ <: BugsPrimType end
struct BugsRange <: BugsPrimType end

abstract type BugsCompoundType <: BugsType end
struct BugsTensor <: BugsCompoundType
    eltype::BugsType
    rank::Int
end

abstract type BugsTransformType <: BugsCompoundType end
struct BugsFun <: BugsTransformType
    dom::ArgsTuple{BugsType}
    cod::BugsType
end
struct BugsDist <: BugsTransformType
    dom::ArgsTuple{BugsType}
    cod::BugsType
end

Base.show(io::IO, t::BugsVoid) = print(io, "Void")
Base.show(io::IO, t::BugsRange) = print(io, "Range")
Base.show(io::IO, t::Bugsℤ) = print(io, "ℤ")
Base.show(io::IO, t::Bugsℝ) = print(io, "ℝ")
Base.show(io::IO, t::BugsFun) = print(io, "(", join(t.dom, ", "), ") → ", t.cod)
Base.show(io::IO, t::BugsDist) = print(io, "(", join(t.dom, ", "), ") ⤳ ", t.cod)
function Base.show(io::IO, t::BugsTensor)
    if t.rank == 0 && t.eltype == Bugsℤ()
        print(io, "Int")
    elseif t.rank == 0 && t.eltype == Bugsℝ()
        print(io, "Real")
    else
        print(io, "Tensor{$(t.eltype), $(t.rank)}")
    end
end
Base.show(io::IO, t::TypeName) = print(io, t.name)

const UncoloredType = Union{TypeName,BugsPrimType,BugsCompoundType}

let _instance = BugsTensor(Bugsℤ(), 0)
    global BugsInt() = _instance
end
let _instance = BugsTensor(Bugsℝ(), 0)
    global BugsReal() = _instance
end

→(dom::BugsType, cod::BugsType) = BugsFun((dom,), cod)
→(dom::Tuple{Vararg{BugsType}}, cod::BugsType) = BugsFun(dom, cod)
↝(dom::BugsType, cod::BugsType) = BugsDist((dom,), cod)
↝(dom::Tuple{Vararg{BugsType}}, cod::BugsType) = BugsDist(dom, cod)

## COLORS ##################
@enum Color constant stochastic ∅
⊑(c1::Color, c2::Color) = c1 ≤ c2
⊔(c1::Color, cs::Color...) = max(c1, cs...)

struct ColoredType <: BugsType
    type::BugsType
    color::Color

    ColoredType(t::BugsType, c::Color) = (c == ∅) ? t : new(t, c)
end

ColoredType(t::ColoredType, c::Color) = ColoredType(t.type, c)
Base.show(io::IO, t::ColoredType) = print(io, "$(t.type) ∙ $(t.color)")

const ∙ = ColoredType
colorof(t::ColoredType) = t.color
colorof(t::BugsType) = ∅
uncolor(t::ColoredType) = t.type
uncolor(t::BugsType) = t

## SUBTYPING ###############
issubtype(t1::BugsType, t2::BugsType) = issubtype(uncolor(t1), uncolor(t2))
issubtype(::BugsType, ::TypeName) = true
issubtype(::TypeName, ::BugsType) = true
issubtype(t1::TypeName, t2::TypeName) = t1 == t2
issubtype(t1::UncoloredType, t2::UncoloredType) = t1 == t2
issubtype(::Bugsℤ, ::Bugsℝ) = true
function issubtype(t1::BugsTensor, t2::BugsTensor)
    return t1.rank == t2.rank && issubtype(t1.eltype, t2.eltype)
end

## UNIFICATION ##############
freevars(t::BugsType) = freevars!(Set{TypeName}(), t)
freevars!(fv, t::TypeName) = push!(fv, t)
freevars!(fv, t::BugsPrimType) = fv
freevars!(fv, t::BugsTransformType) = foldl(freevars!, t.dom; init=freevars!(fv, t.cod))
freevars!(fv, t::BugsTensor) = freevars!(fv, t.eltype)
freevars!(fv, t::ColoredType) = freevars!(fv, uncolor(t))

occursin(n::TypeName, t::TypeName) = n == t
occursin(n::TypeName, t::BugsPrimType) = false
function occursin(n::TypeName, t::BugsTransformType)
    return any(t -> occursin(n, t), t.dom) || occursin(n, t.cod)
end
occursin(n::TypeName, t::BugsTensor) = ocursin(n, t.eltype)
occursin(n::TypeName, t::ColoredType) = occursin(n, uncolor(t))

struct Constraint
    lhs::BugsType
    rhs::BugsType
end
≃(l, r) = Constraint(l, r)
Base.show(io::IO, c::Constraint) = print(io, "$(c.lhs) ≃ $(c.rhs)")

const ConstraintSet = LinkedList{Constraint}

struct Substitution
    mapping::Dict{TypeName,<:BugsType}
end
Substitution(xs...) = Substitution(Dict{TypeName,BugsType}(xs...))

(σ::Substitution)(t::BugsType) = t
(σ::Substitution)(t::BugsFun) = BugsFun(σ.(t.dom), σ(t.cod))
(σ::Substitution)(t::BugsDist) = BugsDist(σ.(t.dom), σ(t.cod))
(σ::Substitution)(t::TypeName) = get(σ.mapping, t, t)

function Base.:∘(σ::Substitution, γ::Substitution)
    mapping = Dict{TypeName,BugsType}()
    for (X, T) in pairs(γ.mapping)
        mapping[X] = σ(T)
    end
    for (X, T) in pairs(σ.mapping)
        get!(γ.mapping, X, T)
    end
    return Substitution(mapping)
end

function unify(𝒞::ConstraintSet)
    if isempty(𝒞)
        return Substitution()
    else
        c, 𝒞′ = pop(𝒞)
        S, T = c.lhs, c.rhs
        if S == T
            return unify(𝒞′)
        elseif S isa TypeName && occursin(S, T)
            σ = Substitution(S => T)
            return unify(σ(𝒞′)) ∘ σ
        elseif T isa TypeName && occursin(T, S)
            σ = Substitution(T => S)
            return unify(σ(𝒞′)) ∘ σ
        elseif S isa BugsFun && T isa BugsFun && length(S.dom) == length(T.dom)
            cs = mapfoldl(
                Base.splat(≃),
                pushfirst!!,
                zip(S.dom, T.dom);
                init=ConstraintSet(S.cod ≃ T.cod),
            )
            return unify(pushfirst!!(𝒞′, cs))
        elseif S isa BugsDist && T isa BugsDist && length(S.dom) == length(T.dom)
            cs = mapfoldl(
                Base.splat(≃),
                pushfirst!!,
                zip(S.dom, T.dom);
                init=ConstraintSet(S.cod ≃ T.cod),
            )
            return unify(pushfirst!!(𝒞′, cs...))
        elseif S isa BugsTensor && T isa BugsTensor && S.rank == T.rank
            return unify(pushfirst!!(𝒞′, S.eltype ≃ T.eltype))
        elseif S isa ColoredType && T isa ColoredType
            return unify(pushfirst!!(𝒞′, S.type ≃ T.type, S.color ≃ T.color))
        else
            error("Could not unify $S and $T")
        end
    end
end

## TYPE CHECKING ###########
const Environment = LinkedList{Pair{Symbol,<:BugsType}}

(σ::Substitution)(Γ::Environment) = map(((n, t),) -> n => σ(t), Γ)
function find(Γ::Environment, key::Symbol)
    return foldr(((k, v), found) -> k == key ? v : found, Γ; init=nothing)
end

function synthesize_color!!(𝒞, Γ, expr)
    if expr isa Symbol
        t_expr = find(Γ, expr)
        if !isnothing(t_expr)
            return 𝒞, Γ, colorof(t_expr)
        else
            t = TypeName(gensym(Symbol("colorof(", expr, ")")))
            return 𝒞, Γ, t
        end
    elseif expr isa Integer
        return 𝒞, Γ, constant
    elseif expr isa AbstractFloat
        return 𝒞, Γ, constant
    elseif Meta.isexpr(expr, :(:), 0)
        return 𝒞, Γ, constant
    elseif Meta.isexpr(expr, :(:), 2)
        l, r = expr.args
        𝒞, Γ = check_color!!(𝒞, Γ, constant)
        𝒞, Γ = check_color!!(𝒞, Γ, constant)
        return 𝒞, Γ, constant
    elseif Meta.isexpr(expr, :ref)
        A, inds = expr.args[1], expr.args[2:end]
        A_rank = length(expr.args)
        𝒞, Γ, A_color = synthesize_color!!(𝒞, Γ, A)
        result_color = A_color
        for ind in inds
            𝒞, Γ, ind_color = synthesize_color!!(𝒞, Γ, ind)
            result_color = result_color ⊔ ind_color
        end
        return 𝒞, Γ, result_color
    elseif Meta.isexpr(expr, :call)
        f, args = expr.args[1], expr.args[2:end]
        𝒞, Γ, f_type = synthesize!!(𝒞, Γ, f)
        if f_type isa BugsFun
            result_color = constant
            for (arg, dom_type) in zip(args, f_type.dom)
                𝒞, Γ, arg_color = synthesize_color!!(𝒞, Γ, arg)
                result_color = result_color ⊔ arg_color
            end
            return 𝒞, Γ, result_color
        elseif t_fun isa BugsDist
            return 𝒞, Γ, stochastic
        else
            error("$f should be a function")
        end
    else
        synthesis_error(expr)
    end
end

function synthesize!!(𝒞, Γ, expr)
    if expr isa Symbol
        name = expr
        name_type = find(Γ, expr)
        if !isnothing(name_type)
            return 𝒞, Γ, name_type
        else
            t = TypeName(gensym(name))
            c = TypeName(gensym(Symbol("colorof(", name, ")")))
            Γ = pushfirst!!(Γ, name => t ∙ c)
            return 𝒞, Γ, t ∙ c
        end
    elseif expr isa Integer
        return 𝒞, Γ, BugsInt() ∙ constant
    elseif expr isa AbstractFloat
        return 𝒞, Γ, BugsReal() ∙ constant
    elseif Meta.isexpr(expr, :(:), 0)
        return 𝒞, Γ, BugsRange() ∙ constant
    elseif Meta.isexpr(expr, :(:), 2)
        l, r = expr.args
        𝒞, Γ = check!!(𝒞, Γ, l, BugsInt())
        𝒞, Γ = check_color!!(𝒞, Γ, l, constant)
        𝒞, Γ = check!!(𝒞, Γ, r, BugsInt())
        𝒞, Γ = check_color!!(𝒞, Γ, r, constant)
        return 𝒞, Γ, BugsRange() ∙ constant
    elseif Meta.isexpr(expr, :ref)
        # This really is just a fancy special case for a function `getindex` with polymorphic type
        # returning an appropriately down-ranked tensor.
        A, inds = expr.args[1], expr.args[2:end]
        A_rank = length(expr.args)
        𝒞, Γ, A_type = synthesize!!(𝒞, Γ, A)
        𝒞, Γ, A_color = synthesize_color!!(𝒞, Γ, A)

        result_color = A_color
        result_rank = 0
        for ind in inds
            𝒞, Γ, ind_type = synthesize!!(𝒞, Γ, ind)
            if issubtype(ind_type, BugsRange())
                result_rank += 1
            elseif !issubtype(ind_type, BugsInt())
                checking_error(ind, BugsInt(), BugsRange())
            end
            𝒞, Γ, ind_color = synthesize_color!!(𝒞, Γ, ind)
            result_color = result_color ⊔ ind_color
        end
        if t_tensor isa BugsTensor
            return 𝒞, Γ, BugsTensor(A_type.eltype, result_rank) ∙ result_color
        else
            t = TypeName(gensym(name))
            return 𝒞, Γ, BugsTensor(result_type, result_rank) ∙ result_color
        end
    elseif Meta.isexpr(expr, :call)
        f, args = expr.args[1], expr.args[2:end]
        𝒞, Γ, t_fun = synthesize!!(𝒞, Γ, f)
        if t_fun isa BugsFun
            c_result = constant
            for (arg, t_dom) in zip(args, t_fun.dom)
                𝒞, Γ, t_arg = synthesize!!(𝒞, Γ, arg)
                !issubtype(t_arg, t_dom) && checking_error(arg, t_dom)
                result_color = result_color ⊔ colorof(t_arg)
            end
            return 𝒞, Γ, t_fun.cod ∙ result_color
        elseif t_fun isa BugsDist
            for (arg, t_dom) in zip(args, t_fun.dom)
                𝒞, Γ, t_arg = check!!(𝒞, Γ, arg, t_dom)
            end
            return 𝒞, Γ, t_fun.cod ∙ stochastic
        else
            checking_error(f, BugsFun, BugsDist)
        end
    else
        synthesis_error(expr)
    end
end

function check!!(𝒞, Γ, expr, t)
    if false

        # elseif Meta.isexpr(expr, :(=)) && t == BugsVoid()
        #     lhs, rhs = expr.args
        #     𝒞, t_left = synthesize!!(𝒞, Γ, lhs)
        #     𝒞 = check!!(𝒞, Γ, rhs, t_left)
        #     return 𝒞
        # elseif Meta.isexpr(expr, :(~)) && t == BugsVoid()
        #     lhs, rhs = expr.args
        #     𝒞, t_left = synthesize!!(𝒞, Γ, lhs)
        #     𝒞 = check!!(𝒞, Γ, lhs, t_left)
        #     return 𝒞
        # elseif Meta.isexpr(expr, :block) && t == BugsVoid()
        #     # new𝒞 = foldl(expr.args; init=𝒞) do (stmt, acc𝒞)
        #         # check(Γ, stmt, BugsVoid, acc𝒞)
        #     # end
        #     # return BugsVoid, new𝒞
        #     return 𝒞
        # elseif Meta.isexpr(expr, :if)

        # elseif Meta.isexpr(expr, :for)
        #     condition, body = expr.args
        #     var, range = condition.args
        #     asserttype(range, BugsInt ∙ constant)
        #     T, new𝒞 = check(push(Γ, var => BugsInt ∙ constant), body, 𝒞)
        #     asserttype()
        #     return BugsVoid, new𝒞
    else
        𝒞, Γ, t_inferred = synthesize!!(𝒞, Γ, expr)
        if t_inferred isa TypeName
            𝒞 = pushfirst!!(𝒞, t_inferred ≃ t)
            return 𝒞, Γ
        elseif issubtype(t_inferred, t)
            return 𝒞, Γ
        else
            checking_error(expr, t)
        end
    end
end

struct BugsTypeError <: Exception
    expr
    expected
end

function Base.showerror(io::IO, e::BugsTypeError)
    if isnothing(e.expected)
        print(io, "could not infer type for `$(e.expr)`")
    elseif eltype(e.expected) <: BugsType
        candidates = join(e.expected, ", ")
        print(io, "expression `$(e.expr)` should have one of the types: `$candidates`")
    else
        candidates = join(e.expected, ", ")
        print(io, "expression `$(e.expr)` should be a subtype of: `$candidates`")
    end
end

checking_error(expr, t_expected...) = throw(BugsTypeError(expr, collect(t_expected)))
synthesis_error(expr) = throw(BugsTypeError(expr, nothing))

function infer_types(expr, Γ_base=Environment())
    𝒞, Γ, t = synthesize!!(ConstraintSet(), Γ_base, expr)
    σ = unify(𝒞)
    return σ(Γ), σ(t)
end

STANDARD_ENV = Environment(:+ => BugsFun((BugsInt(), BugsInt()), BugsInt()))
