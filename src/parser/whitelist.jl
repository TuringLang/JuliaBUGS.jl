# This file defines the whitelists for allowed functions and distributions in @bugs strict mode

# Original BUGS functions that are allowed in strict mode
const BUGS_STRICT_FUNCTIONS = Set{Symbol}([
    # Math functions
    :abs,
    :acos,
    :acosh,
    :arccos,
    :arccosh,
    :asin,
    :asinh,
    :arcsin,
    :arcsinh,
    :atan,
    :atanh,
    :arctan,
    :arctanh,
    :cos,
    :exp,
    :log,
    :sin,
    :sqrt,
    :tan,

    # Link functions
    :cexpexp,
    :cloglog,
    :icloglog,
    :ilogit,
    :logit,
    :logistic,
    :phi,
    :probit,

    # Statistical functions
    :equals,
    :inprod,
    :inverse,
    :logdet,
    :logfact,
    :loggam,
    :max,
    :mean,
    :min,
    :mexp,
    :pow,
    :rank,
    :ranked,
    :round,
    :sd,
    :softplus,
    :sort,
    :sum,
    :_step,
    :trunc,
    :truncated,  # For truncated distributions
    :censored,   # For censored distributions

    # Basic arithmetic operators (always allowed)
    :+,
    :-,
    :*,
    :/,
    :^,

    # BUGS-specific operators
    :~,  # Stochastic assignment operator

    # Indexing and ranges (always allowed)
    :(:),
    :ref,
    :getindex,
])

# Distributions from Distributions.jl that are allowed in strict mode
const DISTRIBUTIONS_STRICT_TYPES = Set{Symbol}([
    # Univariate continuous distributions
    :Normal,
    :LogNormal,
    :Uniform,
    :Beta,
    :Gamma,
    :Exponential,
    :Chisq,
    :TDist,
    :Weibull,
    :Pareto,
    :Laplace,
    :Logistic,
    :InverseGamma,

    # Multivariate distributions
    :MvNormal,
    :Wishart,
    :InverseWishart,
    :Dirichlet,

    # Discrete distributions
    :Bernoulli,
    :Binomial,
    :Categorical,
    :Poisson,
    :NegativeBinomial,
    :DiscreteUniform,
    :Geometric,
    :Hypergeometric,
])

# Distribution-related functions that are allowed
const DISTRIBUTIONS_STRICT_FUNCTIONS = Set{Symbol}([
    :pdf, :logpdf, :cdf, :logcdf, :quantile, :rand
])

# Functions that come from BUGSPrimitives (BUGS-style distribution constructors)
const BUGS_DISTRIBUTION_CONSTRUCTORS = Set{Symbol}([
    :dnorm,
    :dlogis,
    :dt,
    :ddexp,
    :dflat,
    :dexp,
    :dchisqr,
    :dweib,
    :dlnorm,
    :dgamma,
    :dpar,
    :dgev,
    :dgpar,
    :df,
    :dunif,
    :dbeta,
    :dmnorm,
    :dmt,
    :dwish,
    :ddirich,
    :dbern,
    :dbin,
    :dcat,
    :dpois,
    :dnegbin,
    :dhyper,
    :dgeom,
    :dgeom0,
    :dmulti,
])

# Combined whitelist for @bugs strict mode
const BUGS_STRICT_WHITELIST = union(
    BUGS_STRICT_FUNCTIONS,
    DISTRIBUTIONS_STRICT_TYPES,
    DISTRIBUTIONS_STRICT_FUNCTIONS,
    BUGS_DISTRIBUTION_CONSTRUCTORS,
)

"""
    is_function_allowed_bugs_strict(func_name::Symbol)

Check if a function is allowed in @bugs strict mode.
"""
function is_function_allowed_bugs_strict(func_name::Symbol)
    return func_name in BUGS_STRICT_WHITELIST
end

"""
    is_qualified_name_allowed_bugs_strict(module_path::Vector{Symbol}, func_name::Symbol)

Check if a qualified name (e.g., Distributions.Normal) is allowed in @bugs strict mode.
"""
function is_qualified_name_allowed_bugs_strict(
    module_path::Vector{Symbol}, func_name::Symbol
)
    # Special handling for common packages
    if length(module_path) == 1
        if module_path[1] == :Distributions && func_name in DISTRIBUTIONS_STRICT_TYPES
            return true
        elseif module_path[1] == :BUGSPrimitives &&
            func_name in BUGS_DISTRIBUTION_CONSTRUCTORS
            return true
        end
    end

    return false
end

"""
    validate_expression_bugs_strict(expr)

Recursively validate that all function calls in an expression are allowed in @bugs strict mode.
Returns a vector of tuples (disallowed_function, line_number) for all disallowed functions found.
"""
function validate_expression_bugs_strict(expr)
    disallowed = Vector{Tuple{Union{Symbol,Expr},Union{Int,Nothing}}}()

    function get_line_number(e)
        # Try to find a LineNumberNode in the expression
        if e isa Expr
            for arg in e.args
                if arg isa LineNumberNode
                    return arg.line
                end
            end
        end
        return nothing
    end

    function check_expr(e, current_line=nothing)
        if e isa LineNumberNode
            current_line = e.line
        elseif e isa Expr
            if e.head == :call
                func = e.args[1]
                if func isa Symbol
                    if !is_function_allowed_bugs_strict(func)
                        push!(disallowed, (func, current_line))
                    end
                elseif func isa Expr && func.head == :.
                    # Handle qualified names like Distributions.Normal
                    module_path, func_name = decompose_qualified_name(func)
                    if !isempty(module_path) &&
                        !is_qualified_name_allowed_bugs_strict(module_path, func_name)
                        push!(disallowed, (func, current_line))
                    end
                end
            end
            # Recursively check sub-expressions
            for arg in e.args
                check_expr(arg, current_line)
            end
        end
    end

    check_expr(expr)
    return disallowed
end

"""
    decompose_qualified_name(expr::Expr)

Decompose a qualified name expression (e.g., A.B.C) into module path and function name.
Returns (module_path::Vector{Symbol}, func_name::Symbol)
"""
function decompose_qualified_name(expr::Expr)
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
