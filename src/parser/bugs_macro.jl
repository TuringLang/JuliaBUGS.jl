macro bugs(expr::Expr)
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
        check_lhs(expr.args[1], :(=), line_num)
        return Expr(:(=), expr.args[1], bugs_expression(expr.args[2], line_num))
    elseif MacroTools.@capture(expr, lhs_ ~ rhs_)
        check_lhs(lhs, :(~), line_num)
        return Expr(:call, :(~), lhs, bugs_expression(rhs, line_num))
    elseif Meta.isexpr(expr, :for)
        return bugs_for(expr, line_num)
    else
        error(
            "Invalid statement at $line_num: $(expr). Please note that `<-` is not supported, use `=` instead.",
        )
    end
end

function check_lhs(expr::Symbol, assignment_sign, line_num)
    return nothing # no effect
end
function check_lhs(@nospecialize(expr), assignment_sign, line_num)
    if Meta.isexpr(expr, :call)
        if length(expr.args) == 2
            f = expr.args[1]
            inv_f = if f == :log
                :exp
            elseif f == :logit
                :logistic
            elseif f == :cloglog
                :cexpexp
            elseif f == :probit
                :phi
            else
                error(
                    "$(String(expr.args[1])) is not a recognized link function, error at $line_num: $(expr)",
                )
            end

            if assignment_sign === :(=)
                error(
                    "Link function syntax is only supported with the original BUGS input as string, please rewrite the statement by calling the inverse function `$(String(inv_f))` on the RHS, error at $line_num: $(expr)",
                )
            else
                error(
                    "Link function syntax is not allowed in stochastic assignments, error at $line_num: $(expr)",
                )
            end
        else
            error("LHS can only be a scalar or a tensor, error at $line_num: $(expr)")
        end
    elseif Meta.isexpr(expr, :ref)
        if length(expr.args) == 1 # e.g. `x[]`
            error(
                "Implicit indexing in not supported on the LHS, error at $line_num: $(expr)"
            )
        end

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

function bugs_expression(expr, line_num)
    if expr isa Union{Int,Float64,Symbol}
        return expr
    elseif Meta.isexpr(expr, :ref)
        if length(expr.args) == 1 # e.g. `x[]`
            return Expr(:ref, expr.args[1], :(:)) # fill in the colon indexing
        end

        if Meta.isexpr(expr.args[1], :ref) # e.g. `x[1][1]`
            error(
                "BUGS arrays are tensors and do not support nested indexing. Use tensor-style indexing such as `a[i, j]` instead of nested indexing like `a[i][j]`, error at $line_num: $(expr).",
            )
        end

        return Expr(:ref, Base.Fix2(bugs_expression, line_num).(expr.args)...)
    elseif Meta.isexpr(expr, :call)
        if @capture(expr, l_:s_:u_) # range with step is not supported
            error("Range with step is not supported, error at $line_num: $(expr)")
        end
        # special case: `step` is renamed to `_step` to avoid conflict with `Base.step`
        if @capture(expr, step(args__))
            expr.args[1] = :_step
        end

        return Expr(:call, Base.Fix2(bugs_expression, line_num).(expr.args)...)
    elseif Meta.isexpr(expr, :parameters)
        error(
            "Keyword argument syntax is not supported in BUGS, error at $line_num: $(expr)"
        )
    else
        error("Invalid expression at $line_num: `$expr`")
    end
end

"""
    @bugs(program::Expr)
    @bugs(program::String; replace_period::Bool=true, no_enclosure::Bool=false)

Constructs a Julia Abstract Syntax Tree (AST) representation of a BUGS program. This macro supports two forms of input: a Julia expression or a string containing the BUGS program code. 

- When provided with a string, the macro parses it as a BUGS program, with optional arguments to control parsing behavior.
- When given an expression, it performs syntactic checks to ensure compatibility with BUGS syntax.

## Arguments for String Input
For the string input variant, the following optional arguments are available:
- `replace_period::Bool`: When set to `true`, all periods (`.`) in the BUGS code are replaced. This is enabled by default.
- `no_enclosure::Bool`: When `true`, the parser does not require the BUGS program to be enclosed within `model{ ... }` brackets. By default, this is set to `false`.

"""
macro bugs(prog::String, replace_period=true, no_enclosure=false)
    julia_program = to_julia_program(prog, replace_period, no_enclosure)
    expr = Base.Expr(JuliaSyntax.parsestmt(SyntaxNode, julia_program))
    expr = MacroTools.postwalk(MacroTools.rmlines, expr)
    error_container = []
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
                error_msg = (
                    "$(String(f)) is not a recognized link function, at statement $(sub_expr)"
                )
                push!(error_container, :(error($error_msg)))
                return sub_expr
            end
            # The 'rhs' will be parsed into a :block Expr, as the link function syntax is interpreted as a function definition.
            return :($lhs = $inv_f($(rhs.args...)))
        elseif @capture(sub_expr, f_(lhs_) ~ rhs_)
            error_msg = ("Link functions on the LHS of a `~` is not supported at: $(sub_expr)")
            push!(error_container, :(error($error_msg)))
        elseif @capture(sub_expr, step(args__))
            return :(_step($(args...)))
        else
            return sub_expr
        end
    end
    if !isempty(error_container) # otherwise errors thrown in macro will be LoadError
        return :(throw(ErrorException(join($error_container, "\n"))))
    end
    return Meta.quot(expr)
end
