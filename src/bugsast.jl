
position_string(l::LineNumberNode) = string(l.file, ":", l.line)

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
function bugsast_range(expr, position=LineNumberNode(1, nothing))
    if Meta.isexpr(expr, :(:)) && length(expr.args) in (0, 2)
        return Expr(:(:), bugsast_expression.(expr.args, (position,))...)
    elseif Meta.isexpr(expr, :call) && expr.args[1] == :(:) && length(expr.args) in (1, 3)
        return Expr(:(:), bugsast_expression.(expr.args[2:end], (position,))...)
    elseif Meta.isexpr(expr, :$)
        return expr
    else
        error("Illegal range at $(position_string(position)): `$expr`")
    end
end

function bugsast_index(expr, position=LineNumberNode(1, nothing))
    try
        return bugsast_expression(expr, position)
    catch
        return bugsast_range(expr, position)
    end
end

function bugsast_expression(expr, position=LineNumberNode(1, nothing))
    if expr isa Union{Symbol, Number}
        return expr
    elseif Meta.isexpr(expr, :ref)
        return Expr(:ref, bugsast_index.(expr.args, (position,))...)
    elseif Meta.isexpr(expr, :call)
        if expr.args[1] == :getindex
            return Expr(:ref, bugsast_index.(expr.args[2:end], (position,))...)
        elseif expr.args[1] == :truncated || expr.args[1] == :censored
            if length(expr.args) == 4
                return Expr(expr.args[1], bugsast_expression.(expr.args[2:end], (position,))...)
            else
                error("Illegal $(expr.args[1]) form at $(position_string(position)): $expr")
            end
        else
            return Expr(:call, bugsast_expression.(expr.args, (position,))...)
        end
    elseif Meta.isexpr(expr, :block, 2) && expr.args[1] isa LineNumberNode
        # return Expr(:block, expr.args[1], bugsast_expression(expr.args[2]))
        return bugsast_expression(expr.args[2], position)
    elseif Meta.isexpr(expr, :$)
        return expr
    else
        error("Illegal expression at $(position_string(position)): `$expr`")
    end
end

"""
    bugsast_statement(expr)

Check & normalize BUGS blocks, i.e., bodies of `if` and `for` statements.

`LineNumberNode`s are removed, the remaining expressions are checked as statements.
"""
function bugsast_block(expr, position=LineNumberNode(1, nothing))
    if Meta.isexpr(expr, :block)
        stmts = [bugsast_statement(e, position) for e in expr.args if !(e isa LineNumberNode)]
        return Expr(:block, stmts...)
    else
        try
            return Expr(:block, bugsast_statement(expr, position))
        catch
            error("Expression `$expr` at $(position_string(position)) is not a block")
        end
    end
end

"""
    bugsast_statement(expr)

Check & normalize BUGS statements (logical & stochastic assignment, for, if).
"""
function bugsast_statement(expr::Expr, position=LineNumberNode(1, nothing))
    if Meta.isexpr(expr, :(=), 2)
        lhs, rhs = bugsast_expression.(expr.args, (position,))
        check_lhs(lhs)
        return Expr(:(=), lhs, rhs)
    elseif Meta.isexpr(expr, :(~), 2)
        lhs, rhs = bugsast_expression.(expr.args, (position,))
        check_lhs(lhs)
        return Expr(:(~), lhs, rhs)
    elseif Meta.isexpr(expr, :if, 2)
        condition, body = expr.args
        return Expr(:if, bugsast_expression(condition, position), bugsast_block(body, position))
    elseif Meta.isexpr(expr, :for, 2)
        condition, body = expr.args
        if Meta.isexpr(condition, :(=), 2)
            var = condition.args[1]
            range = bugsast_range(condition.args[2], position)
            if !(var isa Symbol)
                error("Illegal loop variable declaration at $(position_string(position)): `$condition`")
            else
                condition = Expr(:(=), var, range)
                return Expr(:for, condition, bugsast_block(body, position))
            end
        else
            error("Invalid loop header at $(position_string(position)): `$condition`")
        end
    elseif Meta.isexpr(expr, :call, 3) && expr.args[1] == :(~)
        return bugsast_statement(Expr(:(~), expr.args[2:end]...), position)
    elseif Meta.isexpr(expr, :block)
        return bugsast_block(expr, position)
    elseif Meta.isexpr(expr, :$)
        return expr
    else
        error("Illegal statement of type `$(expr.head)`")
    end
end

function bugsast(expr, position=LineNumberNode(1, nothing))
    return bugsast_block(expr, position)
end

"""
    @bugsast(expr)

Convert Julia code to an `Expr` that can be used as the AST of a BUGS program.  Checks that only
allowed syntax is used, and normalizes certain expressions.  

Used expression heads: `:~` for tilde calls, `:ref` for indexing, `:(:)` for ranges.  These are
converted from `:call` variants.
"""
macro bugsast(expr)
    return Meta.quot(bugsast(expr, __source__) |> warn_link_function)
end

function warn_link_function(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, f_(lhs_) = rhs_)
            error(
                "BUGS' link function syntax is not supported due to confusion with Julia function definition syntax. " * 
                "Please rewrite logical assignment by calling the inverse of the link function on the RHS. " *
                "Corresponding Inverses: logit => logistic, cloglog => cexpexp, log => exp, probit => phi. "
            )
        end
        return sub_expr
    end
end

function bugs_to_julia(s)
    # remove parentheses around loops
    s = replace(s, r"for\p{Zs}*\((.*)\)\p{Zs}*{" => s"for \1 {")
    
    s = replace(
        s,
        "<-" => "=",
        # blocks in if and for replaced by respective delimiters (; ≃ \n)
        "{" => ";",
        "}" => "end",
        # empty slices (with lookahead to replace multiple in a series)
        r"\[\p{Zs}*\]" => "[:]",
        r"\[\p{Zs}*(?=,)" => "[:",
        r",\p{Zs}*(?=[,\]])" => ",:",
        # ignore reserved words (\b is word boundary)
        r"\b(in|for|if|C|T)\b" => s"\1",
        # ignore floats (could otherwise overlap with identifiers: ., E, e)
        r"(((\p{N}+\.\p{N}+)|(\p{N}+\.?))([eE][+-]?\p{N}+)?)" => s"\1",
        # wrap variable names in var-strings (to allow variable names with .)
        r"((?:(?:\p{L}\p{M}*)|\.)(?:(?:\p{L}\p{M}*)|\.|\p{N})*)" => s"var\"\1\"", 
    )

    # special censoring/truncation syntax is converted to function calls, with `nothing`
    # inserted for left-out bounds
    s = replace(
        s,
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*T\p{Zs}*\(\p{Zs}*,(.+)\)" => s"truncated(\1, nothing, \2)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*T\p{Zs}*\((.+),\p{Zs}*\)" => s"truncated(\1, \2, nothing)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*T\p{Zs}*\((.+),(.+)\)" => s"truncated(\1, \2, \3)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*C\p{Zs}*\(\p{Zs}*,(.+)\)" => s"censored(\1, nothing, \2)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*C\p{Zs}*\((.+),\p{Zs}*\)" => s"censored(\1, \2, nothing)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*C\p{Zs}*\((.+),(.+)\)" => s"censored(\1, \2, \3)",
    )

    return s
end

macro bugsmodel_str(s::String)
    # Convert and wrap the whole thing in a block for parsing
    transformed_code = "begin\n$(bugs_to_julia(s))\nend"
    try
        expr = Meta.parse(transformed_code)
        return Meta.quot(bugsast(expr, __source__))
    catch e
        if e isa Base.Meta.ParseError
            # Meta.parse automatically uses file name "none" and position 1, so
            # I think this should always work?
            new_msg = replace(e.msg, "none:1" => position_string(__source__))
            rethrow(ErrorException(new_msg))
        else
            rethrow()
        end
    end
end


