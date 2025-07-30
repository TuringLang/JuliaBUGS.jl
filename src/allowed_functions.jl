"""
Manages the allowlist of functions that can be used in @bugs macro expressions.
Only functions in this allowlist or registered via @bugs_primitive are permitted.
"""

# Global set of allowed function names for @bugs macro
const BUGS_ALLOWED_FUNCTIONS = Set{Symbol}()

"""
    is_function_allowed(func_name::Symbol)

Check if a function is allowed to be used in @bugs expressions.
"""
is_function_allowed(func_name::Symbol) = func_name in BUGS_ALLOWED_FUNCTIONS

"""
    register_bugs_function(func_name::Symbol)

Register a function to be allowed in @bugs expressions.
Used by @bugs_primitive macro.
"""
function register_bugs_function(func_name::Symbol)
    push!(BUGS_ALLOWED_FUNCTIONS, func_name)
end

"""
    validate_bugs_expression(expr, line_num)

Validate that all function calls in the expression are allowed.
Throws an error if an unregistered function is found.
"""
function validate_bugs_expression(expr, line_num)
    if expr isa Symbol || expr isa Number
        return nothing  # Base cases are fine
    elseif Meta.isexpr(expr, :call)
        func_name = expr.args[1]

        # Check for qualified function names (e.g., Base.exp, Distributions.Normal)
        if Meta.isexpr(func_name, :.)
            qualified_expr = func_name
            unqualified_name =
                if Meta.isexpr(qualified_expr, :.) && length(qualified_expr.args) >= 2
                    # For expressions like Base.exp, extract :exp
                    qualified_expr.args[2].value
                else
                    qualified_expr
                end
            error(
                "Qualified function names are not supported in @bugs. Found $(qualified_expr) at $line_num. " *
                "To use custom functions, declare them with @bugs_primitive macro. " *
                "Otherwise, use the unqualified function name `$(unqualified_name)` instead.",
            )
        elseif func_name isa Symbol && !is_function_allowed(func_name)
            error(
                "Function '$func_name' is not allowed in @bugs at $line_num. " *
                "To use custom functions, declare them with @bugs_primitive macro.",
            )
        end
        # Recursively validate arguments
        for arg in expr.args[2:end]
            validate_bugs_expression(arg, line_num)
        end
    elseif Meta.isexpr(expr, :ref)
        # Validate array indexing expressions
        for arg in expr.args
            validate_bugs_expression(arg, line_num)
        end
    elseif Meta.isexpr(expr, :block)
        # Validate block expressions
        for arg in expr.args
            if !(arg isa LineNumberNode)
                validate_bugs_expression(arg, line_num)
            end
        end
    elseif Meta.isexpr(expr, :for)
        # Validate for loop expressions
        validate_bugs_expression(expr.args[2], line_num)  # loop body
    elseif Meta.isexpr(expr, :(=))
        # For assignments, validate both LHS (in case of array indexing) and RHS
        validate_bugs_expression(expr.args[1], line_num)
        validate_bugs_expression(expr.args[2], line_num)
    end
end
