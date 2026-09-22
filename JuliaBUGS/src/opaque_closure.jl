# Retain the ordinary Julia closure in `source` for AD, serialization, and
# respecialization. It can be retained or precompiled with the model. For each
# argument signature, infer IR from `source` in the current world and lazily
# compile a `Core.OpaqueClosure` there. Opaque closures are process-, world-, and
# signature-specific runtime caches: they are reused within a process but
# regenerated after deserialization or in a new process, rather than serialized.
mutable struct _OpaqueClosureFunction{F} <: Function
    const source::F
    # The last specialization avoids a lock and dictionary lookup on repeated calls.
    @atomic closure::Any
    specializations::Dict{Type,Any}
    lock::ReentrantLock
end

function _prepare_opaque_closure(f::_OpaqueClosureFunction, signature::Type{<:Tuple})
    return lock(f.lock) do
        get!(f.specializations, signature) do
            world = Base.get_world_counter()
            ir, _ = only(Base.code_ircode(f.source, signature; world))
            # OpaqueClosure passes captured values as a tuple in the first IR argument.
            ir.argtypes[1] = Tuple{typeof(f.source)}
            Base.invoke_in_world(world, Core.OpaqueClosure, ir, f.source; do_compile=true)
        end
    end
end

_opaque_signature(::Core.OpaqueClosure{Args,R}) where {Args,R} = Args

function (f::_OpaqueClosureFunction)(a::A, b::B) where {A,B}
    # Ordinary inference can recover the result type on hot calls. A source just
    # created by eval may still be newer than the caller's world, hence the fallback.
    R = Core.Compiler.return_type(f.source, Tuple{A,B})
    R = R === Union{} ? Any : R
    if ccall(:jl_generating_output, Cint, ()) == 1
        return Base.invokelatest(f.source, a, b)::R
    end
    # Type-valued results can have a narrower return type, e.g. Type{Float64} vs DataType.
    C = if isconcretetype(R) && !(R <: Type)
        Core.OpaqueClosure{Tuple{A,B},R}
    else
        Core.OpaqueClosure
    end
    closure = @atomic :acquire f.closure
    if !(closure isa C && _opaque_signature(closure) === Tuple{A,B})
        closure = _prepare_opaque_closure(f, Tuple{A,B})
        @atomic :release f.closure = closure
    end
    return (closure::C)(a, b)::R
end

function _make_opaque_closure(
    function_expr::Expr, eval_module::Module, owner_module::Module=eval_module
)
    # Native macro hygiene resolves globals in eval_module while defining the
    # function in its owner's package image. In particular, generated evaluation
    # keeps JuliaBUGS's namespace without mutating it during precompilation.
    expr = if owner_module === eval_module
        function_expr
    else
        Expr(Symbol("hygienic-scope"), function_expr, eval_module)
    end
    source = Core.eval(owner_module, expr)
    return _OpaqueClosureFunction(source, nothing, Dict{Type,Any}(), ReentrantLock())
end

_opaque_source(f) = f
_opaque_source(f::_OpaqueClosureFunction) = f.source

function _prepare_opaque_gradient(adtype, model, x)
    Model._supports_mutation(adtype) ||
        return Model._prepare_logdensity_gradient(adtype, model, x)
    # Mooncake and Enzyme see ordinary functions; the base model retains its caches.
    gd = model.graph_evaluation_data
    gd = @set gd.node_function_vals = map(_opaque_source, gd.node_function_vals)
    g = copy(model.g)
    for vn in labels(g)
        node = g[vn]
        g[vn] = @set node.node_function = _opaque_source(node.node_function)
    end
    source_model = Model.BUGSModel(
        model;
        g,
        # Provenance is not used by density evaluation and can retain executable caches.
        base_model=nothing,
        graph_evaluation_data=gd,
        log_density_computation_function=_opaque_source(
            model.log_density_computation_function
        ),
    )
    # Source functions were created by eval and may be newer than this caller.
    return Base.invokelatest(Model._prepare_logdensity_gradient, adtype, source_model, x)
end
