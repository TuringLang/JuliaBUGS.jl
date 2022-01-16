check_lhs(expr) = check_lhs(Bool, expr) || error("Invalid LHS expression `$expr`")
check_lhs(::Type{Bool}, expr) = false
check_lhs(::Type{Bool}, ::Symbol) = true
function check_lhs(::Type{Bool}, expr::Expr)
    return Meta.isexpr(expr, :ref) ||
        (Meta.isexpr(expr, :call, 2) && check_lhs(Bool, expr.args[2]))
end

"""
    jbugs_expression(expr)

Check & normalize BUGS expressions (function calls, variables, literals, indexed variables).
"""
function jbugs_expression end

"""
    jbugs_range(expr)

Check & normalize BUGS ranges.
"""
function jbugs_range(expr)
    if Meta.isexpr(expr, :(:)) && length(expr.args) in (0, 2)
        return Expr(:(:), jbugs_expression.(expr.args)...)
    elseif Meta.isexpr(expr, :call) && expr.args[1] == :(:) && length(expr.args) in (1, 3)
        return Expr(:(:), jbugs_expression.(expr.args[2:end])...)
    else
        error("Illegal range: `$expr`")
    end
end

function jbugs_index(expr)
    try
        return jbugs_expression(expr)
    catch
        return jbugs_range(expr)
    end
end

function jbugs_expression(expr)
    if expr isa Union{Symbol, Number}
        return expr
    elseif Meta.isexpr(expr, :ref)
        return Expr(:ref, jbugs_index.(expr.args)...)
    elseif Meta.isexpr(expr, :call)
        if expr.args[1] == :getindex
            return Expr(:ref, jbugs_index.(expr.args[2:end])...)
        else
            return Expr(:call, jbugs_expression.(expr.args)...)
        end
    elseif Meta.isexpr(expr, :block, 2) && expr.args[1] isa LineNumberNode
        return Expr(:block, expr.args[1], jbugs_expression(expr.args[2]))
    else
        error("Illegal expression: `$expr`")
    end
end

function jbugs_block(expr)
    if Meta.isexpr(expr, :block)
        stmts = [jbugs_statement(e) for e in expr.args if !(e isa LineNumberNode)]
        return Expr(:block, stmts...)
    else
        try
            return Expr(:block, jbugs_statement(expr))
        catch
            error("Expression `$expr` is not a block")
        end
    end
end

"""
    jbugs_statement(expr)

Check & normalize BUGS statements (logical & stochastic assignment, for, if).
"""
function jbugs_statement(expr::Expr)
    if Meta.isexpr(expr, :(=), 2)
        lhs, rhs = jbugs_expression.(expr.args)
        check_lhs(lhs)
        return Expr(:(=), lhs, rhs)
    elseif Meta.isexpr(expr, :(~), 2)
        lhs, rhs = jbugs_expression.(expr.args)
        check_lhs(lhs)
        return Expr(:(~), lhs, rhs)
    elseif Meta.isexpr(expr, :if, 2)
        condition, body = expr.args
        return Expr(:if, jbugs_expression(condition), jbugs_block(body))
    elseif Meta.isexpr(expr, :for, 2)
        condition, body = expr.args
        if Meta.isexpr(condition, :(=), 2)
            var = condition.args[1]
            range = jbugs_range(condition.args[2])
            if !(var isa Symbol)
                error("Illegal loop variable declaration: `$condition`")
            else
                condition = Expr(:(=), var, range)
                return Expr(:for, condition, jbugs_block(body))
            end
        else
            error("Invalid loop header: `$condition`")
        end
    elseif Meta.isexpr(expr, :call, 3) && expr.args[1] == :(~)
        return jbugs_statement(Expr(:(~), expr.args[2:end]...))
    elseif Meta.isexpr(expr, :block)
        return jbugs_block(expr)
    else
        error("Illegal statement of type `$(expr.head)`")
    end
end

function jbugs(expr)
    return jbugs_block(expr)
end

"""
    @bugsast(expr)

Convert Julia code to an `Expr` that can be used as the AST of a BUGS program.  Checks that only
allowed syntax is used, and normalizes certain expressions.  

Used expression heads: `:~` for tilde calls, `:ref` for indexing, `:(:)` for ranges.  These are
converted from `:call` variants.
"""
macro bugsast(expr)
    return QuoteNode(jbugs(expr))
end
