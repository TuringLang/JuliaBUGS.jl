check_lhs(expr) = check_lhs(Bool, expr) || error("Invalid LHS expression `$expr`")
check_lhs(::Type{Bool}, expr) = false
check_lhs(::Type{Bool}, ::Symbol) = true
function check_lhs(::Type{Bool}, expr::Expr)
    return Meta.isexpr(expr, :ref) ||
        (Meta.isexpr(expr, :call, 2) && check_lhs(Bool, expr.args[2]))
end

"""
    bugsast_expression(expr)

Check & normalize BUGS expressions (function calls, variables, literals, indexed variables).
"""
function bugsast_expression end

"""
    bugsast_range(expr)

Check & normalize BUGS ranges.
"""
function bugsast_range(expr)
    if Meta.isexpr(expr, :(:)) && length(expr.args) in (0, 2)
        return Expr(:(:), bugsast_expression.(expr.args)...)
    elseif Meta.isexpr(expr, :call) && expr.args[1] == :(:) && length(expr.args) in (1, 3)
        return Expr(:(:), bugsast_expression.(expr.args[2:end])...)
    else
        error("Illegal range: `$expr`")
    end
end

function bugsast_index(expr)
    try
        return bugsast_expression(expr)
    catch
        return bugsast_range(expr)
    end
end

function bugsast_expression(expr)
    if expr isa Union{Symbol, Number}
        return expr
    elseif Meta.isexpr(expr, :ref)
        return Expr(:ref, bugsast_index.(expr.args)...)
    elseif Meta.isexpr(expr, :call)
        if expr.args[1] == :getindex
            return Expr(:ref, bugsast_index.(expr.args[2:end])...)
        elseif expr.args[1] == :truncated || expr.args[1] == :censored
            return Expr(expr.args[1], bugsast_expression.(expr.args[2:end])...)
        else
            return Expr(:call, bugsast_expression.(expr.args)...)
        end
    elseif Meta.isexpr(expr, :block, 2) && expr.args[1] isa LineNumberNode
        # return Expr(:block, expr.args[1], bugsast_expression(expr.args[2]))
        return bugsast_expression(expr.args[2])
    else
        error("Illegal expression: `$expr`")
    end
end

function bugsast_block(expr)
    if Meta.isexpr(expr, :block)
        stmts = [bugsast_statement(e) for e in expr.args if !(e isa LineNumberNode)]
        return Expr(:block, stmts...)
    else
        try
            return Expr(:block, bugsast_statement(expr))
        catch
            error("Expression `$expr` is not a block")
        end
    end
end

"""
    bugsast_statement(expr)

Check & normalize BUGS statements (logical & stochastic assignment, for, if).
"""
function bugsast_statement(expr::Expr)
    if Meta.isexpr(expr, :(=), 2)
        lhs, rhs = bugsast_expression.(expr.args)
        check_lhs(lhs)
        return Expr(:(=), lhs, rhs)
    elseif Meta.isexpr(expr, :(~), 2)
        lhs, rhs = bugsast_expression.(expr.args)
        check_lhs(lhs)
        return Expr(:(~), lhs, rhs)
    elseif Meta.isexpr(expr, :if, 2)
        condition, body = expr.args
        return Expr(:if, bugsast_expression(condition), bugsast_block(body))
    elseif Meta.isexpr(expr, :for, 2)
        condition, body = expr.args
        if Meta.isexpr(condition, :(=), 2)
            var = condition.args[1]
            range = bugsast_range(condition.args[2])
            if !(var isa Symbol)
                error("Illegal loop variable declaration: `$condition`")
            else
                condition = Expr(:(=), var, range)
                return Expr(:for, condition, bugsast_block(body))
            end
        else
            error("Invalid loop header: `$condition`")
        end
    elseif Meta.isexpr(expr, :call, 3) && expr.args[1] == :(~)
        return bugsast_statement(Expr(:(~), expr.args[2:end]...))
    elseif Meta.isexpr(expr, :block)
        return bugsast_block(expr)
    else
        error("Illegal statement of type `$(expr.head)`")
    end
end

function bugsast(expr)
    return bugsast_block(expr)
end

"""
    @bugsast(expr)

Convert Julia code to an `Expr` that can be used as the AST of a BUGS program.  Checks that only
allowed syntax is used, and normalizes certain expressions.  

Used expression heads: `:~` for tilde calls, `:ref` for indexing, `:(:)` for ranges.  These are
converted from `:call` variants.
"""
macro bugsast(expr)
    return QuoteNode(bugsast(expr))
end


macro bugsmodel_str(s)
    # remove parentheses around loops
    transformed_code = replace(s, r"for\p{Zs}*\((.*)\)\p{Zs}*{" => s"for \1 {")
    transformed_code = replace(
        transformed_code,
        "<-" => "=",
        # blocks in if and for replaced by respective delimiters (; ≃ \n)
        "{" => ";",
        "}" => "end",
        # empty slices (with lookahead to replace multiple in a series)
        r"\[\p{Zs}*(?=,)" => "[:",
        r",\p{Zs}*(?=[,\]])" => ",:",
        # ignore reserved words (\b is word boundary)
        r"\b(in|for|if|C|T)\b" => s"\1",
        # ignore floats (could otherwise overlap with identifiers: ., E, e)
        r"(((\p{N}+\.\p{N}+)|(\p{N}+\.?))([eE][+-]?\p{N}+)?)" => s"\1",
        # wrap variable names in var-strings (to allow variable names with .)
        r"((?:(?:\p{L}\p{M}*)|\.)(?:(?:\p{L}\p{M}*)|\.|\p{N})*)" => s"var\"\1\"", 
    )
    transformed_code = replace(
        transformed_code,
        r"(var\"[^\"]+\"\(.*\))\p{Zs}*T\p{Zs}*\(\p{Zs}*,(.+)\)" => s"truncated(\1, nothing, \2)",
        r"(var\"[^\"]+\"\(.*\))\p{Zs}*T\p{Zs}*\((.+),\p{Zs}*\)" => s"truncated(\1, \2, nothing)",
        r"(var\"[^\"]+\"\(.*\))\p{Zs}*T\p{Zs}*\((.+),(.+)\)" => s"truncated(\1, \2, \3)",
        r"(var\"[^\"]+\"\(.*\))\p{Zs}*C\p{Zs}*\(\p{Zs}*,(.+)\)" => s"censored(\1, nothing, \2)",
        r"(var\"[^\"]+\"\(.*\))\p{Zs}*C\p{Zs}*\((.+),\p{Zs}*\)" => s"censored(\1, \2, nothing)",
        r"(var\"[^\"]+\"\(.*\))\p{Zs}*C\p{Zs}*\((.+),(.+)\)" => s"censored(\1, \2, \3)",
    )
    # wrap the whole thing in a block
    transformed_code = "begin\n$transformed_code\nend"
    # println(transformed_code)
    
    expr = Meta.parse(transformed_code)
    return QuoteNode(bugsast(expr))
end
