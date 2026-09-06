module JuliaBUGSMooncakeExt

using JuliaBUGS
using Mooncake

struct MistyClosureRRule{R}
    rule::R
end

Mooncake._copy(x::MistyClosureRRule) = MistyClosureRRule(Mooncake._copy(x.rule))

@inline function (rule::MistyClosureRRule)(::Mooncake.CoDual, args::Mooncake.CoDual...)
    return rule.rule(Mooncake.zero_fcodual(()), args...)
end

Mooncake.@is_primitive Mooncake.MinimalCtx Mooncake.ReverseMode Tuple{
    JuliaBUGS._MistyClosureFunction,Vararg{Any,N}
} where {N}

function _interpreter_and_method(
    ::Type{T}, mode
) where {ID,F<:JuliaBUGS._MistyClosureFunction{ID},T<:Tuple{F,Vararg}}
    entry = JuliaBUGS._misty_closure_entry(ID)
    signature = Tuple{Tuple{},T.parameters[2:end]...}
    mi = Core.Compiler.specialize_method(entry.source, signature, Core.svec())
    interpreter = Mooncake.MooncakeInterpreter(Mooncake.DefaultCtx, mode; world=entry.world)
    return interpreter, mi
end

# Deriving a rule here resets Mooncake's instruction IDs during the enclosing AD pass.
function Mooncake.build_primitive_rrule(
    ::Type{T}
) where {T<:Tuple{JuliaBUGS._MistyClosureFunction,Vararg}}
    interpreter, mi = _interpreter_and_method(T, Mooncake.ReverseMode)
    R = Mooncake.rule_type(interpreter, mi; debug_mode=false)
    rule = Mooncake.LazyDerivedRule{mi.specTypes,R}(mi, false, interpreter.world)
    return MistyClosureRRule(rule)
end

struct MistyClosureFRule{R}
    rule::R
end

Mooncake._copy(x::MistyClosureFRule) = MistyClosureFRule(Mooncake._copy(x.rule))

@inline function (rule::MistyClosureFRule)(::Mooncake.Dual, args::Mooncake.Dual...)
    return rule.rule(Mooncake.zero_dual(()), args...)
end

Mooncake.@is_primitive Mooncake.MinimalCtx Mooncake.ForwardMode Tuple{
    JuliaBUGS._MistyClosureFunction,Vararg{Any,N}
} where {N}

function Mooncake.build_primitive_frule(
    ::Type{T}
) where {T<:Tuple{JuliaBUGS._MistyClosureFunction,Vararg}}
    interpreter, mi = _interpreter_and_method(T, Mooncake.ForwardMode)
    R = Mooncake.frule_type(interpreter, mi; debug_mode=false)
    rule = Mooncake.LazyFRule{mi.specTypes,R}(mi, false, interpreter.world)
    return MistyClosureFRule(rule)
end

end
