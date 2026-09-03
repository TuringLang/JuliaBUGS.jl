struct _MistyClosureEntry
    signature::DataType
    closure::MistyClosure
    function_expr::Expr
    eval_module::Module
    fallback_closures::Dict{DataType,MistyClosure}
    lock::ReentrantLock
end

struct _MistyClosureFunction{ID} <: Function end

const _MISTY_CLOSURE_ENTRIES = Dict{Symbol,_MistyClosureEntry}()
const _MISTY_CLOSURE_IDS = Dict{Tuple{Module,Expr,DataType,UInt},Symbol}()
const _MISTY_CLOSURE_LOCK = ReentrantLock()

function _compile_misty_closure(
    function_expr::Expr,
    eval_module::Module,
    signature::Type{<:Tuple},
    ;
    optimize_until=nothing,
)
    # Evaluating `@opaque` creates no global method; `MistyClosure` retains its inferred IR.
    opaque_closure = Core.eval(eval_module, :(Base.Experimental.@opaque $function_expr))
    interpreter = Core.Compiler.NativeInterpreter(UInt(opaque_closure.world))
    argument_types = Tuple{Tuple{},signature.parameters...}
    ir, _ = Core.Compiler.typeinf_ircode(
        interpreter, opaque_closure.source, argument_types, Core.svec(), optimize_until
    )
    ir.argtypes[1] = Tuple{}
    return MistyClosure(ir; do_compile=true)
end

@generated function (::_MistyClosureFunction{ID})(
    first_argument::A, second_argument::B
) where {ID,A,B}
    entry = _MISTY_CLOSURE_ENTRIES[ID]
    # Avoid boxing constant results when the callable is stored behind an abstract field.
    ir = entry.closure.ir[]
    if length(ir.cfg.blocks) == 1
        return_node = @static if VERSION >= v"1.12"
            last(ir.stmts.stmt)
        else
            last(ir.stmts.inst)
        end
        if return_node isa Core.ReturnNode &&
            isdefined(return_node, :val) &&
            return_node.val isa QuoteNode
            return return_node.val
        end
    end
    if Tuple{A,B} <: entry.signature
        return :($(entry.closure)(first_argument, second_argument))
    end
    return :(_call_fallback_misty_closure(
        $(QuoteNode(ID)), first_argument, second_argument
    ))
end

function _get_misty_closure(id::Symbol, signature::DataType)
    entry = _MISTY_CLOSURE_ENTRIES[id]
    signature <: entry.signature && return entry.closure
    return lock(entry.lock) do
        get!(entry.fallback_closures, signature) do
            _compile_misty_closure(entry.function_expr, entry.eval_module, signature)
        end
    end
end

Base.@noinline function _call_fallback_misty_closure(
    id::Symbol, first_argument::A, second_argument::B
) where {A,B}
    closure = _get_misty_closure(id, Tuple{A,B})
    return closure(first_argument, second_argument)
end

function _make_misty_closure(
    function_expr::Expr, eval_module::Module, signature::Type{<:Tuple}
)
    closure = _compile_misty_closure(function_expr, eval_module, signature)
    key = (eval_module, function_expr, signature, UInt(closure.oc.world))
    id = lock(_MISTY_CLOSURE_LOCK) do
        get!(_MISTY_CLOSURE_IDS, key) do
            id = gensym(:misty_closure)
            _MISTY_CLOSURE_ENTRIES[id] = _MistyClosureEntry(
                signature,
                closure,
                function_expr,
                eval_module,
                Dict{DataType,MistyClosure}(),
                ReentrantLock(),
            )
            return id
        end
    end
    return _MistyClosureFunction{id}()
end

function _specialize_node_functions(
    g::BUGSGraph, evaluation_env::NamedTuple, eval_module::Module
)
    specialized = Dict{Tuple{Expr,DataType},Function}()
    new_g = copy(g)
    for vn in labels(new_g)
        node_info = new_g[vn]
        key = (node_info.node_function_expr, typeof(node_info.loop_vars))
        node_function = get!(specialized, key) do
            signature = Tuple{typeof(evaluation_env),typeof(node_info.loop_vars)}
            _make_misty_closure(node_info.node_function_expr, eval_module, signature)
        end
        new_g[vn] = BangBang.setproperty!!(node_info, :node_function, node_function)
    end
    return new_g
end
