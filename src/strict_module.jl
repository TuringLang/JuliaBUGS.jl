# This module provides a controlled environment for @bugs macro evaluation
# It only imports the whitelisted functions and distributions

"""
    create_bugs_strict_module()

Create a new module with only whitelisted functions and functions registered via @bugs_primitive.
"""
function create_bugs_strict_module()
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

    # Import all functions that were registered via @bugs_primitive
    # They are stored in the JuliaBUGS module
    for name in names(JuliaBUGS; all=true)
        # Skip special names and modules
        if startswith(string(name), "#") ||
            name in (:eval, :include) ||
            name in names(Core) ||
            name in names(Base) ||
            name in (:JuliaBUGS, :BUGSPrimitives, :Parser, :Model) ||
            # Skip symbols that are already imported from BUGSPrimitives or Distributions
            name in BUGSPrimitives.BUGS_FUNCTIONS ||
            name in BUGSPrimitives.BUGS_DISTRIBUTIONS
            continue
        end

        # Try to get the value to check if it's a function
        try
            val = getfield(JuliaBUGS, name)
            if isa(val, Function) && !isa(val, Type)
                # Import the function into the strict module
                Core.eval(strict_module, :(using JuliaBUGS: $name))
            end
        catch
            # Skip if we can't access it
            continue
        end
    end

    return strict_module
end
