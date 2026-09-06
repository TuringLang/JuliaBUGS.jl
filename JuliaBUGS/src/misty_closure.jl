struct _MistyClosureEntry
    source::Method
    world::UInt
end

struct _MistyClosureFunction{ID} <: Function end

const _MISTY_CLOSURE_ENTRIES = Dict{Symbol,_MistyClosureEntry}()
const _MISTY_CLOSURE_IDS = Dict{Tuple{Module,Expr,UInt},Symbol}()
const _MISTY_CLOSURE_LOCK = Threads.SpinLock()

function _infer_misty_closure(entry::_MistyClosureEntry, signature::Type{<:Tuple})
    interpreter = Core.Compiler.NativeInterpreter(entry.world)
    argument_types = Tuple{Tuple{},signature.parameters...}
    ir, rt = Core.Compiler.typeinf_ircode(
        interpreter, entry.source, argument_types, Core.svec(), nothing
    )
    ir.argtypes[1] = Tuple{}
    return ir, Core.Compiler.widenconst(rt)
end

function _misty_closure_entry(id::Symbol)
    return lock(_MISTY_CLOSURE_LOCK) do
        _MISTY_CLOSURE_ENTRIES[id]
    end
end

# Generated functions run in an older world; construct their opaque closures on
# first execution so dynamic calls use the retained source world.
mutable struct _MistyClosureSpecialization{C}
    @atomic closure::Union{Nothing,C}
    ir::Core.Compiler.IRCode
    world::UInt
    lock::ReentrantLock
end

Base.@noinline function _initialize_misty_closure(
    cache::_MistyClosureSpecialization{C}
) where {C}
    return lock(cache.lock) do
        closure = @atomic :acquire cache.closure
        if closure === nothing
            closure = Base.invoke_in_world(
                cache.world, MistyClosure, cache.ir; do_compile=true
            )::C
            @atomic :release cache.closure = closure
        end
        closure::C
    end
end

@inline function _call_misty_closure(
    cache::_MistyClosureSpecialization, first_argument, second_argument
)
    closure = @atomic :acquire cache.closure
    if closure === nothing
        closure = _initialize_misty_closure(cache)
    end
    return closure(first_argument, second_argument)
end

@generated function (::_MistyClosureFunction{ID})(
    first_argument::A, second_argument::B
) where {ID,A,B}
    entry = _misty_closure_entry(ID)
    ir, rt = _infer_misty_closure(entry, Tuple{A,B})
    if length(ir.stmts) == 1
        return_node = @static if VERSION >= v"1.11"
            only(ir.stmts.stmt)
        else
            only(ir.stmts.inst)
        end
        if return_node isa Core.ReturnNode &&
            isdefined(return_node, :val) &&
            return_node.val isa QuoteNode
            return return_node.val
        end
    end
    C = MistyClosure{Core.OpaqueClosure{Tuple{A,B},rt}}
    cache = _MistyClosureSpecialization{C}(nothing, ir, entry.world, ReentrantLock())
    return :(_call_misty_closure($cache, first_argument, second_argument))
end

function _make_misty_closure(function_expr::Expr, eval_module::Module)
    key = (eval_module, function_expr, Base.get_world_counter())
    id = lock(_MISTY_CLOSURE_LOCK) do
        get(_MISTY_CLOSURE_IDS, key, nothing)
    end
    id !== nothing && return _MistyClosureFunction{id}()
    oc = Core.eval(eval_module, :(Base.Experimental.@opaque $function_expr))
    entry = _MistyClosureEntry(oc.source, oc.world)
    id = lock(_MISTY_CLOSURE_LOCK) do
        get!(_MISTY_CLOSURE_IDS, (eval_module, copy(function_expr), entry.world)) do
            id = gensym(:misty_closure)
            _MISTY_CLOSURE_ENTRIES[id] = entry
            id
        end
    end
    return _MistyClosureFunction{id}()
end
