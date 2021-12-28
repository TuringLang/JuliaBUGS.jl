check_lhs(expr) = check_lhs(Bool, expr) || error("Invalid LHS expression `$expr`")
check_lhs(::Type{Bool}, expr) = false
check_lhs(::Type{Bool}, ::Symbol) = true
function check_lhs(::Type{Bool}, expr::Expr)
    if Meta.isexpr(expr, :ref)
        return true
    elseif Meta.isexpr(expr, :call, 2) && check_lhs(Bool, expr.args[2])
        return true
    else
        return false
    end
end

"""
    jbugs_expr(expr)

Check & normalize BUGS expressions (function calls, indexing).
"""
function jbugs_expr end

"""
    jbugs_expr(expr)

Check & normalize BUGS ranges.
"""
function jbugs_range(expr)
    if Meta.isexpr(expr, :(:), 2)
        return Expr(:(:), jbugs_expr.(expr.args)...)
    elseif Meta.isexpr(expr, :call, 3) && expr.args[1] == :(:)
        return Expr(:(:), jbugs_expr(expr.args[2]), jbugs_expr(expr.args[3]))
    else
        error("Illegal range: `$expr`")
    end
end



function jbugs_index(expr)
    try
        return jbugs_expr(expr)
    catch
        return jbugs_range(expr)
    end
end

function jbugs_expr(expr)
    if expr isa Union{Symbol, Number}
        return expr
    elseif Meta.isexpr(expr, :ref)
        return Expr(:ref, jbugs_index.(expr.args)...)
    elseif Meta.isexpr(expr, :call)
        if expr.args[1] == :getindex
            return Expr(:ref, jbugs_index.(expr.args[2:end])...)
        else
            return Expr(:call, jbugs_expr.(expr.args)...)
        end
    else
        error("Illegal expression: `$expr`")
    end
end

"""
    jbugs_stmt(expr)

Check & normalize BUGS statements (logical & stochastic assignment, for, if).
"""
function jbugs_stmt(expr::Expr)
    if Meta.isexpr(expr, :(=), 2)
        lhs, rhs = jbugs_expr.(expr.args)
        check_lhs(lhs)
        return Expr(:(=), lhs, rhs)
    elseif Meta.isexpr(expr, :(~), 2)
        lhs, rhs = jbugs_expr.(expr.args)
        check_lhs(lhs)
        return Expr(:(~), lhs, rhs)
    elseif Meta.isexpr(expr, :if, 2)
        condition, body = expr.args
        return Expr(:if, jbugs_expr(condition), jbugs_stmt(expr))
    elseif Meta.isexpr(expr, :for, 2)
        condition, body = expr.args
        if Meta.isexpr(condition, :(=), 2)
            var = condition.args[1]
            range = jbugs_range(condition.args[2])
            if !(var isa Symbol)
                error("Illegal loop variable declaration: `$condition`")
            else
                condition = Expr(:(=), var, range)
                return Expr(:for, condition, [jbugs_stmt(e) for e in body.args if !(e isa LineNumberNode)]...)
            end
        else
            error("Invalid loop header: `$condition`")
        end
    elseif Meta.isexpr(expr, :call, 3) && expr.args[1] == :(~)
        return jbugs_stmt(Expr(:(~), expr.args[2:end]...))
    elseif Meta.isexpr(expr, :block)
        return Expr(:block, [jbugs_stmt(e) for e in expr.args if !(e isa LineNumberNode)]...)
    else
        error("Illegal statement of type `$(expr.head)`")
    end
end

function jbugs(expr)
    if Meta.isexpr(expr, :block)
        return Expr(:block, [jbugs_stmt(e) for e in expr.args if !(e isa LineNumberNode)]...)
    else
        error("Expression is not a block")
    end
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
