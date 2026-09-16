# The source belongs to the callable. Specializations are runtime caches: neither
# opaque closures nor process-local world ages may be saved in a package image.
mutable struct _MistyClosureFunction{F} <: Function
    const source::F
    @atomic closure::Any
    specializations::Dict{Type,Any}
    lock::ReentrantLock
end

function _prepare_misty_closure(f::_MistyClosureFunction, signature::Type{<:Tuple})
    return lock(f.lock) do
        get!(f.specializations, signature) do
            world = Base.get_world_counter()
            interpreter = Core.Compiler.NativeInterpreter(world)
            argument_types = Tuple{typeof(f.source),signature.parameters...}
            method = which(f.source, signature)
            ir, _ = Core.Compiler.typeinf_ircode(
                interpreter, method, argument_types, Core.svec(), nothing
            )
            ir.argtypes[1] = Tuple{typeof(f.source)}
            Base.invoke_in_world(world, MistyClosure, ir, f.source; do_compile=true)
        end
    end
end

_misty_signature(::MistyClosure{Core.OpaqueClosure{Args,R}}) where {Args,R} = Args

function (f::_MistyClosureFunction)(a::A, b::B) where {A,B}
    # Ordinary inference can recover the result type on hot calls. A source just
    # created by eval may still be newer than the caller's world, hence the fallback.
    R = Core.Compiler.return_type(f.source, Tuple{A,B})
    R = R === Union{} ? Any : R
    if ccall(:jl_generating_output, Cint, ()) == 1
        return Base.invokelatest(f.source, a, b)::R
    end
    C = isconcretetype(R) ? MistyClosure{Core.OpaqueClosure{Tuple{A,B},R}} : MistyClosure
    closure = @atomic :acquire f.closure
    if !(closure isa C && _misty_signature(closure) === Tuple{A,B})
        closure = _prepare_misty_closure(f, Tuple{A,B})
        @atomic :release f.closure = closure
    end
    return (closure::C)(a, b)::R
end

function _make_misty_closure(
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
    return _MistyClosureFunction(source, nothing, Dict{Type,Any}(), ReentrantLock())
end
