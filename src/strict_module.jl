# This module provides a controlled environment for @bugs macro evaluation
# It only imports the whitelisted functions and distributions

"""
    create_bugs_strict_module(allowed_extras::Set{Union{Symbol,Expr}}=Set{Union{Symbol,Expr}}())

Create a new module with only whitelisted functions and any additional allowed functions.
"""
function create_bugs_strict_module(
    allowed_extras::Set{Union{Symbol,Expr}}=Set{Union{Symbol,Expr}}()
)
    # Create a unique module name to avoid conflicts
    module_name = gensym("BUGSStrictModule")

    # Build the module expression
    mod_expr = quote
        module $module_name

        using ..BUGSPrimitives
        using Distributions:
            Normal,
            LogNormal,
            Uniform,
            Beta,
            Gamma,
            Exponential,
            Chisq,
            TDist,
            Weibull,
            Pareto,
            Laplace,
            Logistic,
            InverseGamma,
            MvNormal,
            Wishart,
            InverseWishart,
            Dirichlet,
            Bernoulli,
            Binomial,
            Categorical,
            Poisson,
            NegativeBinomial,
            DiscreteUniform,
            Geometric,
            Hypergeometric,
            pdf,
            logpdf,
            cdf,
            logcdf,
            quantile,
            rand

        # Re-export all BUGS primitives
        $([:(using ..BUGSPrimitives: $func) for func in BUGSPrimitives.BUGS_FUNCTIONS]...)

        # Re-export all BUGS distribution constructors
        $(
            [
                :(using ..BUGSPrimitives: $dist) for
                dist in BUGSPrimitives.BUGS_DISTRIBUTIONS
            ]...
        )

        end # module
    end

    # Evaluate the module at the top level in Main to avoid "module expression not at top level" error
    strict_module = Core.eval(Main, mod_expr)

    # Now add any extra allowed functions
    for item in allowed_extras
        if item isa Symbol
            # Try to import from Main first, then from parent modules
            try
                Core.eval(strict_module, :(using Main: $item))
            catch
                # If not in Main, user needs to use qualified name
                @warn "Function $item not found in Main. Use qualified name (e.g., MyModule.$item) instead."
            end
        elseif item isa Expr && item.head == :.
            # Handle qualified names like MyModule.func
            # Extract module path and function name
            module_path, func_name = decompose_qualified_import(item)
            if !isempty(module_path)
                # Build import statement
                import_expr = build_import_expr(module_path, func_name)
                try
                    Core.eval(strict_module, import_expr)
                catch e
                    @warn "Could not import $item: $e"
                end
            end
        end
    end

    return strict_module
end

"""
    decompose_qualified_import(expr::Expr)

Decompose a qualified name for import purposes.
"""
function decompose_qualified_import(expr::Expr)
    # Similar to decompose_qualified_name but for import statements
    if expr.head != :.
        return Symbol[], :nothing
    end

    path = Symbol[]
    current = expr

    while current isa Expr && current.head == :.
        if length(current.args) == 2 && current.args[2] isa QuoteNode
            pushfirst!(path, current.args[2].value)
            current = current.args[1]
        else
            break
        end
    end

    if current isa Symbol
        pushfirst!(path, current)
    end

    if length(path) < 2
        return Symbol[], :nothing
    end

    return path[1:(end - 1)], path[end]
end

"""
    build_import_expr(module_path::Vector{Symbol}, func_name::Symbol)

Build an import expression from module path and function name.
"""
function build_import_expr(module_path::Vector{Symbol}, func_name::Symbol)
    # Build nested module access
    mod_expr = module_path[1]
    for m in module_path[2:end]
        mod_expr = Expr(:., mod_expr, QuoteNode(m))
    end

    # Build the import statement
    return :(using $mod_expr: $func_name)
end
