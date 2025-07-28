"""
    create_bugs_eval_module()

Create a new module with only exported functions from BUGSPrimitives and functions 
registered via @bugs_primitive. This provides a restricted evaluation environment 
for @bugs macro expressions.
"""
function create_bugs_eval_module()
    # Create the module using Base.Module
    eval_module = Module(:BUGSEvalModule)

    # Import all exported names from BUGSPrimitives into the new module
    for name in names(BUGSPrimitives; all=false)
        if isdefined(BUGSPrimitives, name)
            Core.eval(eval_module, :(const $name = $BUGSPrimitives.$name))
        end
    end

    # Import all functions that were registered via @bugs_primitive
    # They are stored as bindings in the JuliaBUGS module
    # Use all=true to get non-exported names too
    for name in names(@__MODULE__; all=true)
        # Skip special names, modules, and types
        if startswith(string(name), "#") || name in (:eval, :include)
            continue
        end

        if isdefined(@__MODULE__, name)
            val = getfield(@__MODULE__, name)
            if isa(val, Function) && !isa(val, Type)
                # Check if it's not already imported from BUGSPrimitives
                if !(name in names(BUGSPrimitives; all=false))
                    try
                        # Import the function into the eval module
                        Core.eval(eval_module, :(const $name = $(@__MODULE__).$name))
                    catch
                        # Skip if we can't import it
                    end
                end
            end
        end
    end

    return eval_module
end

# Create a singleton instance for the default BUGS evaluation module
const _default_bugs_eval_module = Ref{Module}()

"""
    get_default_bugs_eval_module()

Get the default evaluation module for BUGS expressions. Creates it on first use.
"""
function get_default_bugs_eval_module()
    if !isassigned(_default_bugs_eval_module)
        _default_bugs_eval_module[] = create_bugs_eval_module()
    end
    return _default_bugs_eval_module[]
end
