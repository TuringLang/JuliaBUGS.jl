module JuliaBUGSMooncakeExt

using JuliaBUGS
using Mooncake

struct MistyClosureRRule{R}
    rule::R
end

@inline function (rule::MistyClosureRRule)(::Mooncake.CoDual, args::Mooncake.CoDual...)
    result, pullback = rule.rule(Mooncake.zero_fcodual(()), args...)
    return result, MistyClosurePullback(pullback)
end

struct MistyClosurePullback{P}
    pullback::P
end

@inline function (pullback::MistyClosurePullback)(output_rdata)
    result = pullback.pullback(output_rdata)
    return (Mooncake.NoRData(), Base.tail(result)...)
end

Mooncake.@is_primitive Mooncake.MinimalCtx Mooncake.ReverseMode Tuple{
    JuliaBUGS._MistyClosureFunction,Vararg{Any,N}
} where {N}

function _closure_and_world(
    ::Type{T}
) where {ID,F<:JuliaBUGS._MistyClosureFunction{ID},T<:Tuple{F,Vararg}}
    signature = Tuple{T.parameters[2:end]...}
    entry = JuliaBUGS._MISTY_CLOSURE_ENTRIES[ID]
    # Preserve call boundaries so Mooncake can apply rules before Julia lowers them to ccalls.
    closure = JuliaBUGS._compile_misty_closure(
        entry.function_expr, entry.eval_module, signature; optimize_until="compact 1"
    )
    world = @static if VERSION >= v"1.12"
        UInt(closure.ir[].valid_worlds.max_world)
    else
        UInt(closure.oc.world)
    end
    return closure, world
end

function Mooncake.build_primitive_rrule(
    ::Type{T}
) where {T<:Tuple{JuliaBUGS._MistyClosureFunction,Vararg}}
    closure, world = _closure_and_world(T)
    interpreter = Mooncake.MooncakeInterpreter(
        Mooncake.DefaultCtx, Mooncake.ReverseMode; world
    )
    rule = Mooncake.build_rrule(interpreter, closure; skip_world_age_check=true)
    return MistyClosureRRule(rule)
end

end
