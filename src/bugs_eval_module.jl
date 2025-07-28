"""
    create_bugs_eval_module()

Create a new module with only exported functions from BUGSPrimitives.
This provides a restricted evaluation environment for @bugs macro expressions.
Functions can be added via @bugs_primitive.
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
