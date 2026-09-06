module JuliaBUGSMooncakeExt

using JuliaBUGS
using Mooncake

struct MistyClosureRRule{R}
    rule::R
end

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

function Mooncake.build_primitive_rrule(
    ::Type{T}
) where {T<:Tuple{JuliaBUGS._MistyClosureFunction,Vararg}}
    interpreter, mi = _interpreter_and_method(T, Mooncake.ReverseMode)
    rule = Mooncake.build_rrule(interpreter, mi; skip_world_age_check=true)
    return MistyClosureRRule(rule)
end

struct MistyClosureFRule{R}
    rule::R
end

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
    rule = Mooncake.build_frule(interpreter, mi; skip_world_age_check=true)
    return MistyClosureFRule(rule)
end

end
