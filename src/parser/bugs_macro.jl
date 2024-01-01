macro bugs(expr)
    return Meta.quot(bugs_top(expr, __source__))
end

function bugs_top(@nospecialize(expr), __source__)
    if Meta.isexpr(expr, :block)
        return Expr(:block, bugs_block_body(expr, __source__)...)
    elseif Meta.isexpr(expr, (:(=), :for)) || MacroTools.@capture(expr, lhs_ ~ rhs_)
        return bugs_statement(expr, __source__)
    else
        error("Invalid model definition.")
    end
end

function bugs_block_body(@nospecialize(expr), __source__)
    if !(expr.args[1] isa LineNumberNode) # if the model is given using parentheses, the first line is not a LineNumberNode
        expr.args = [__source__, expr.args...]
    end
    return [
        bugs_statement(stmt, line_num) for (line_num, stmt) in
        Iterators.take(Iterators.partition(expr.args, 2), length(expr.args) ÷ 2) # the last line is the LineNumberNode for `end`
    ]
end

function bugs_statement(@nospecialize(expr), line_num)
    if Meta.isexpr(expr, :(=))
        check_lhs(expr.args[1], line_num)
        return Expr(:(=), expr.args[1], bugs_expression(expr.args[2], line_num))
    elseif MacroTools.@capture(expr, lhs_ ~ rhs_)
        check_lhs(lhs, line_num)
        return Expr(:call, :(~), lhs, bugs_expression(rhs, line_num))
    elseif Meta.isexpr(expr, :for)
        return bugs_for(expr, line_num)
    end
end

check_lhs(expr::Symbol, line_num) = nothing # no effect
function check_lhs(@nospecialize(expr), line_num)
    if Meta.isexpr(expr, :call)
        if length(expr.args) == 2
            error(LINK_FUNCTION_ERROR_MSG)
        else
            error("Invalid LHS at $line_num: $(expr)")
        end
    elseif Meta.isexpr(expr, :ref)
        return Base.Fix2(bugs_expression, line_num).(expr.args)
    else
        error("Invalid LHS at $line_num: $(expr)")
    end
end

function bugs_for(@nospecialize(expr), line_num)
    if MacroTools.@capture(
        expr,
        for i_ in lower_:upper_
            body_
        end
    )
        i isa Symbol || error("Loop variable must be a scalar, at $line_num: $(i)")
        lower, upper = Base.Fix2(bugs_expression, line_num).((lower, upper))
        return MacroTools.@q for $i in ($lower):($upper)
            $(bugs_block_body(body, line_num)...)
        end
    else
        error("Invalid for loop: $(expr) at $line_num")
    end
end

function bugs_expression(@nospecialize(expr), line_num)
    if expr isa Union{Int,Float64,Symbol}
        return expr
    elseif Meta.isexpr(expr, :ref)
        # special cases
        if length(expr.args) == 1 # e.g. `x[]`
            return Expr(:ref, expr.args[1], :(:)) # fill in the colon indexing
        elseif Meta.isexpr(expr.args[1], :ref)
            error(
                "BUGS arrays are tensors and do not support nested indexing. Use tensor-style indexing such as `a[i, j]` instead of nested indexing like `a[i][j]` at line $line_num.",
            )
        end

        return Expr(:ref, Base.Fix2(bugs_expression, line_num).(expr.args)...)
    elseif Meta.isexpr(expr, :call)
        # range with step is not supported
        if expr.args[1] == :(:) && length(expr.args) == 4
            error("Range with step is not supported at $line_num: $(expr)")
        end

        return Expr(:call, Base.Fix2(bugs_expression, line_num).(expr.args)...)
    else
        error("Invalid expression at $line_num: `$expr`")
    end
end

"""
    @bugs(prog::String, replace_period=true, no_enclosure=false)

Produce similar output as [`@bugs`](@ref), but takes a string as input.  This is useful for 
parsing original BUGS programs.

# Arguments
- `prog::String`: The BUGS program code as a string.
- `replace_period::Bool`: If true, periods in the BUGS code will be replaced (default `true`).
- `no_enclosure::Bool`: If true, the parser will not expect the program to be wrapped between `model{ }` (default `false`).

"""
macro bugs(prog::String, replace_period=true, no_enclosure=false)
    julia_program = to_julia_program(prog, replace_period, no_enclosure)
    expr = Base.Expr(JuliaSyntax.parsestmt(SyntaxNode, julia_program))
    expr = MacroTools.postwalk(MacroTools.rmlines, expr)
    expr = MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, f_(lhs_) = rhs_) # only transform logical assignments
            inv_f = if f == :log
                :exp
            elseif f == :logit
                :logistic
            elseif f == :cloglog
                :cexpexp
            elseif f == :probit
                :phi
            else
                error("Not supported")
            end
            # The 'rhs' will be parsed into a :block Expr, as the link function syntax is interpreted as a function definition.
            return :($lhs = $inv_f($(rhs.args...)))
        elseif @capture(sub_expr, f_(lhs_) ~ rhs_)
            error("Link functions on the LHS of a `~` is not supported: $sub_expr")
        else
            return sub_expr
        end
    end
    return Meta.quot(expr)
end
