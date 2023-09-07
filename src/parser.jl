using JuliaSyntax
using JuliaSyntax: @K_str, @KSet_str, tokenize, untokenize, Diagnostic, Token

mutable struct ProcessState
    token_vec::Vector{Token}
    current_index::Int
    text::String
    julia_token_vec::Vector{Any}
    diagnostics::Vector{Diagnostic}
    replace_period::Bool
    allow_eq::Bool
end

function ProcessState(text::String, replace_period=true, allow_eq=true)
    token_vec = filter(x -> kind(x) != K"error", tokenize(text)) # generic "error" is disregarded
    disallowed_words = Token[]
    for t in token_vec
        if kind(t) ∉ WHITELIST
            push!(disallowed_words, t)
        end
    end
    if !isempty(disallowed_words)
        diagnostics = Diagnostic[]
        for w in disallowed_words
            if JuliaSyntax.is_error(w) || kind(w) == K"ErrorInvalidOperator"
                error = "Error occurs, error kind is $(string(kind(w))), characters are $(untokenize(w, text))"
            else
                error = "Disallowed word '$(untokenize(w, text))'"
            end
            push!(diagnostics, Diagnostic(w.range.start, w.range.stop, :error, error))
        end
        io = IOBuffer()
        JuliaSyntax.show_diagnostics(io, diagnostics, text)
        error("Errors occurs while tokenizing: \n $(String(take!(io)))")
    end
    return ProcessState(token_vec, 1, text, Any[], Diagnostic[], replace_period, allow_eq)
end

# Julia's reserved words are not allowed to be used as variable names
WHITELIST = KSet"Whitespace Comment NewlineWs EndMarker for in , { } ( ) [ ] : ; ~ < - <-- = + - * / ^ . Identifier Integer Float TOMBSTONE error"

function ProcessState(ps::ProcessState)
    return ProcessState(
        ps.token_vec,
        ps.current_index,
        ps.text,
        deepcopy(ps.julia_token_vec),
        deepcopy(ps.diagnostics),
        ps.replace_period,
        ps.allow_eq,
    )
end

function consume!(ps::ProcessState, substitute=nothing)
    if isnothing(substitute)
        push!(ps.julia_token_vec, ps.token_vec[ps.current_index])
    else
        push!(ps.julia_token_vec, substitute)
    end
    return ps.current_index += 1
end

function discard!(ps::ProcessState)
    return ps.current_index += 1
end

function expect!(ps::ProcessState, expected::String, substitute=nothing)
    process_trivia!(ps)
    if peek_raw(ps) != expected
        add_diagnostic!(ps, "Expecting '$expected'")
    else
        consume!(ps, substitute)
    end
end

function expect!(ps::ProcessState, expected::Tuple, substitute=nothing)
    process_trivia!(ps)
    if peek_raw(ps) ∉ expected
        add_diagnostic!(ps, "Expecting '$expected'")
    else
        consume!(ps, substitute)
    end
end

function expect_and_discard!(ps::ProcessState, expected::String)
    process_trivia!(ps)
    if peek_raw(ps) != expected
        add_diagnostic!(ps, "Expecting '$expected'")
    else
        discard!(ps)
    end
end

function add_diagnostic!(ps, msg::String)
    # check if the current token is EOF
    if ps.current_index > length(ps.token_vec)
        diagnostic = JuliaSyntax.Diagnostic(0, 0, :error, msg)
        @assert diagnostic ∉ ps.diagnostics
        push!(ps.diagnostics, diagnostic)
        return nothing
    end
    low = first(ps.token_vec[ps.current_index].range)
    high = last(ps.token_vec[ps.current_index].range)
    diagnostic = JuliaSyntax.Diagnostic(low, high, :error, msg)

    if any((x -> x.first_byte == low).(ps.diagnostics))
        io = IOBuffer()
        JuliaSyntax.show_diagnostics(io, ps.diagnostics, ps.text)
        println(String(take!(io)))
        error("Encounter duplicated error, aborting.")
    end
    return push!(ps.diagnostics, diagnostic)
end

function peek(ps::ProcessState, n=1)
    if ps.current_index + n - 1 > length(ps.token_vec)
        return K"EndMarker"
    end
    return kind(ps.token_vec[ps.current_index + n - 1])
end

function peek_raw(ps::ProcessState, n=1)
    if ps.current_index + n - 1 > length(ps.token_vec)
        return "EOF"
    end
    return untokenize(ps.token_vec[ps.current_index + n - 1], ps.text)
end

function peek_next_non_trivia(ps::ProcessState, skip_newline=true, n=1)
    if ps.current_index + n - 1 > length(ps.token_vec)
        return K"EndMarker"
    end

    trivia_tokens = KSet"Whitespace Comment"
    skip_newline && (trivia_tokens = trivia_tokens ∪ KSet"NewlineWs")

    seek_index = ps.current_index
    token_count = 0
    while token_count <= n
        while kind(ps.token_vec[seek_index]) ∈ trivia_tokens
            seek_index += 1
            if seek_index > length(ps.token_vec)
                return K"EndMarker"
            end
        end
        token_count += 1
    end
    return kind(ps.token_vec[seek_index])
end

function simulate(process_function, ps::ProcessState, args...) # ps is always the first argument of process_functions
    ps_copy = ProcessState(ps)
    (process_function)(ps_copy, args...)
    return ps_copy
end

function look_back(ps::ProcessState, n=1)
    if n > length(ps.julia_token_vec)
        return K"TOMBSTONE"
    end
    return kind(ps.julia_token_vec[end - n + 1])
end

function process_trivia!(ps::ProcessState, skip_newline=true)
    trivia_tokens = KSet"Whitespace Comment"
    skip_newline && (trivia_tokens = (trivia_tokens ∪ KSet"NewlineWs"))
    while peek(ps) ∈ trivia_tokens
        consume!(ps)
    end
end

function process_toplevel!(ps::ProcessState)
    expect_and_discard!(ps, "model")
    expect!(ps, "{", "begin")
    process_statements!(ps)
    if peek(ps) != K"}"
        add_diagnostic!(
            ps,
            "Parsing finished without get to the end of the program. $(peek_raw(ps)) is not expected to lead an statement.",
        )
    end
    expect!(ps, "}", "end")
    return process_trivia!(ps)
end

function process_toplevel_no_enclosure!(ps::ProcessState)
    push!(ps.julia_token_vec, "begin \n")
    process_statements!(ps)
    push!(ps.julia_token_vec, "\n end")
    return process_trivia!(ps)
end

function process_statements!(ps::ProcessState)
    process_trivia!(ps)
    while peek(ps) ∈ KSet"for Identifier"
        if peek(ps) == K"for"
            process_for!(ps)
        else # peek(ps) == K"Identifier"
            process_assignment!(ps)
        end
        process_trivia!(ps)
    end
end

function process_assignment!(ps::ProcessState)
    process_lhs!(ps)

    if peek(ps) == K"~"
        consume!(ps)
        process_tilde_rhs!(ps)
        process_trivia!(ps)
        return nothing
    end

    if ps.allow_eq && peek(ps) == K"="
        consume!(ps)
    elseif peek(ps) == K"<" && peek(ps, 2) == K"-"
        discard!(ps) # discard the "<"
        discard!(ps) # discard the "-"
        push!(ps.julia_token_vec, "=")
    elseif peek(ps) == K"<" &&
        peek(ps, 2) ∈ KSet"Integer Float" &&
        startswith(peek_raw(ps, 2), "-") # special case: `a <-1` is tokenized as `a`, `<`, and `-1`
        t = ps.token_vec[ps.current_index]
        low = t.range.start
        high = t.range.stop
        replaced_tokens = [
            Token(JuliaSyntax.SyntaxHead(K"-", JuliaSyntax.EMPTY_FLAGS), low:(low + 1)),
            Token(t.head, (low + 1):high),
        ]
        splice!(ps.token_vec, ps.current_index, replaced_tokens)
        discard!(ps) # discard the "<"
        discard!(ps) # discard the "-"
        push!(ps.julia_token_vec, "=")
    elseif peek(ps) == K"<--"
        discard!(ps) # discard the "<--"
        push!(ps.julia_token_vec, "=")
        push!(ps.julia_token_vec, "-")
        process_identifier_led_expression!(ps)
    else
        allowed_assignment_signs = ["~", "<-"]
        if ps.allow_eq
            push!(allowed_assignment_signs, "=")
        end
        add_diagnostic!(ps, "Expecting $(join(allowed_assignment_signs, ", "))")
    end

    process_expression!(ps)
    return process_trivia!(ps)
end

function process_lhs!(ps::ProcessState)
    if peek_raw(ps) ∈ ("logit", "cloglog", "log", "probit") && peek(ps, 2) != K"." # link functions 
        consume!(ps) # consume the link function
        expect!(ps, "(")
        process_variable!(ps) # link functions can only take one argument
        process_trivia!(ps)
        expect!(ps, ")")
    elseif any(Base.Fix1(startswith, peek_raw(ps)).(["logit", "cloglog", "log", "probit"]))
        # missing left parentheses if right parentheses is present
        ps_copy = simulate(process_variable!, ps)
        if peek(ps_copy) == K")"
            add_diagnostic!(ps, "Missing left parentheses")
        else # then it's just a variable name start with one of "logit", "cloglog", "log", "probit"
            process_variable!(ps)
        end
    else
        process_variable!(ps)
    end
    return process_trivia!(ps)
end

function process_for!(ps)
    consume!(ps) # consume the "for"

    expect_and_discard!(ps, "(")
    if peek(ps) == K"Identifier"
        push!(ps.julia_token_vec, " ") # add white space between "for" and the loop variable
    end

    process_variable!(ps)
    expect!(ps, "in")

    process_range!(ps)
    expect_and_discard!(ps, ")")

    expect_and_discard!(ps, "{")
    process_statements!(ps)
    return expect!(ps, "}", " end") # add extra white space in case of "}}"
end

function process_range!(ps)
    process_expression!(ps, KSet": , ]")
    expect!(ps, ":")
    return process_expression!(ps, KSet")")
end

function process_expression!(
    ps::ProcessState, terminators=KSet"; NewlineWs EndMarker { } for , "
)
    process_trivia!(ps)
    if peek(ps) ∈ KSet"+ -" # only allow a single + or - at the beginning
        consume!(ps)
    end
    return process_identifier_led_expression!(ps, terminators)
end

function process_identifier_led_expression!(ps, terminators=KSet"; NewlineWs EndMarker")
    process_trivia!(ps)
    if peek(ps) ∈ terminators
        return nothing
    end
    while true
        if peek(ps) ∈ KSet"Integer Float"
            # `-2` will be tokenized to token `-2`, which means the current design allow "- -2"
            # Julia handles this well and in a intuitive way; may not be native to BUGS, but
            # it's a unambiguous syntax, so we allow it
            consume!(ps)
        elseif peek(ps) == K"Identifier"
            if peek(ps, 2) == K"("
                consume!(ps) # consume the function name
                consume!(ps) # consume the "("
                process_call_args!(ps)
                expect!(ps, ")")
            else
                process_variable!(ps) # "a.b(args)" falls into this case
                if peek(ps) == K"("
                    consume!(ps) # consume the "("
                    process_call_args!(ps)
                    expect!(ps, ")")
                end
            end
        elseif peek(ps) == K"(" # maybe function call args or just a parenthesized expression
            consume!(ps)
            process_expression!(ps, KSet")")
            expect!(ps, ")")
        end
        process_trivia!(ps, false)

        if peek_next_non_trivia(ps) ∈ KSet"+ - * / ^"
            while peek(ps) == K"NewlineWs"
                discard!(ps)
            end
        elseif peek(ps) ∈ terminators
            if peek(ps) == K";" # others will be consumed by process_trivia!
                consume!(ps)
            elseif peek(ps) == K"for" # in case of `for(i in 1:10)`, otherwise `fori ...`
                push!(ps.julia_token_vec, "\n")
            end
            return nothing
        end

        if peek(ps) ∈ KSet"+ - * / ^"
            consume!(ps)
        elseif peek(ps) ∈ KSet"Integer Float" && startswith(peek_raw(ps), "-")
            push!(ps.julia_token_vec, "- ")
            push!(ps.julia_token_vec, peek_raw(ps)[2:end])
            discard!(ps)
        elseif peek(ps) ∈ KSet"Identifier for" # heuristic: the ";" is forgotten, so insert one
            push!(ps.julia_token_vec, ";")
            process_statements!(ps)
        else
            add_diagnostic!(
                ps, "Expecting operator none of + - * / ^, but got $(peek_raw(ps))"
            )
        end
        process_trivia!(ps)
    end
end

function process_tilde_rhs!(ps::ProcessState)
    buffer = Any[]
    julia_token_vec = ps.julia_token_vec
    ps.julia_token_vec = buffer
    process_trivia!(ps)
    process_variable!(ps)
    expect!(ps, "(")
    process_call_args!(ps)
    expect!(ps, ")")
    process_trivia!(ps, false) # allow whitespace 
    if peek_raw(ps) in ["T", "C"]
        discard!(ps) # discard the "T" or "C"
        expect_and_discard!(ps, "(")
        push!(julia_token_vec, peek_raw(ps) == "C" ? " censored(" : " truncated(")
        push!(julia_token_vec, buffer..., ", ")
        ps.julia_token_vec = julia_token_vec
        if peek_next_non_trivia(ps) == K","
            push!(julia_token_vec, "nothing")
        else
            process_expression!(ps, KSet",")
        end
        expect!(ps, ",")
        if peek_next_non_trivia(ps) == K")"
            push!(ps.julia_token_vec, "nothing")
        else
            process_expression!(ps, KSet")")
        end
        expect!(ps, ")")
        if peek(ps) == K";"
            consume!(ps)
        end
        return nothing
    end

    push!(julia_token_vec, buffer...)
    ps.julia_token_vec = julia_token_vec

    if peek(ps) == K";"
        consume!(ps)
    elseif peek_next_non_trivia(ps, false) == K"Identifier" # heuristic: the ";" is forgotten, so insert one
        push!(julia_token_vec, ";")
    end
end

function process_variable!(ps::ProcessState, allow_indexing=true)
    process_trivia!(ps)

    # if a simple variable, just consume it and return
    if peek(ps, 2) ∉ KSet". ["
        consume!(ps)
        return nothing
    end

    # deal with cases like `a.b.c` and `a.b.c[i]`
    if peek(ps, 2) == K"."
        if peek(ps, 3) != K"Identifier"
            add_diagnostic!(ps, "Variable names can't end with '.'.")

            return nothing
        end
        variable_name_buffer = String[]
        while peek(ps) == K"Identifier"
            push!(variable_name_buffer, peek_raw(ps))
            discard!(ps)
            if peek(ps) != K"."
                break
            end
            discard!(ps) # discard the "."
        end

        if ps.replace_period
            push!(ps.julia_token_vec, join(variable_name_buffer, "_"))
        else
            push!(ps.julia_token_vec, "var\"$(join(variable_name_buffer, "."))\"")
        end

        if peek(ps) != K"["
            return nothing
        elseif peek(simulate(process_trivia!, ps)) == K"]"
            add_diagnostic!(
                ps, "Whitespace is not allowed between variable name and indexing."
            )
            process_trivia!(ps)
        end
    else
        consume!(ps)
    end

    if allow_indexing
        process_indexing!(ps)
    end
end

function process_indexing!(ps::ProcessState)
    expect!(ps, "[")
    while true
        if peek(ps) == K"EndMarker"
            break
        end
        process_trivia!(ps)
        if peek(ps) ∈ KSet", ]"
            push!(ps.julia_token_vec, ":")
        else
            process_index!(ps)
        end
        process_trivia!(ps)
        if peek(ps) == K"]"
            break
        else
            expect!(ps, ",")
        end
    end
    return expect!(ps, "]")
end

# index can be expression, or range
function process_index!(ps)
    process_expression!(ps, KSet": , ]")
    if peek_raw(ps) == ":"
        consume!(ps)
        process_expression!(ps, KSet", ]")
    end
end

function process_call_args!(ps)
    process_trivia!(ps)
    while peek(ps) != "," && peek(ps) != "EndMarker"
        process_expression!(ps, KSet", ) EndMarker")
        if peek(ps) == K")"
            break
        end
        expect!(ps, ",")
        process_trivia!(ps)
    end
end

function to_julia_program(ps::ProcessState)
    return to_julia_program(ps.julia_token_vec, ps.text)
end
function to_julia_program(julia_token_vec, text)
    program = ""
    for t in julia_token_vec
        if t isa String
            program *= t
        else
            str = untokenize(t, text)
            program *= str
        end
    end
    return program
end

"""
    to_julia_program

Convert a BUGS program to a Julia program.

# Arguments
- `prog::String`: A string containing the BUGS program that needs to be converted.
- `replace_period::Bool=true`: A flag to determine whether periods should be replaced in the 
conversion process. If `true`, periods in variable names or other relevant places will be 
replaced with an underscore. If `false`, periods will be retained, and variable name will be
wrapped in `var"..."` to avoid syntax error.
- `no_enclosure::Bool=false`: A flag to determine the enclosure processing strategy. 
If `true`, the parse will not enforce the requirement that the program body to be enclosed in
"model { ... }". 

"""
function to_julia_program(prog::String, replace_period=true, no_enclosure=false)
    ps = ProcessState(prog, replace_period)
    if no_enclosure
        process_toplevel_no_enclosure!(ps)
    else
        process_toplevel!(ps)
    end
    if !isempty(ps.diagnostics)
        io = IOBuffer()
        JuliaSyntax.show_diagnostics(io, ps.diagnostics, ps.text)
        error("Errors in the program: \n $(String(take!(io)))")
    end
    return to_julia_program(ps.julia_token_vec, ps.text)
end

# end of parser
# start of @bugs macro related code

"""
    bugsast_range(expr)

Check and normalize BUGS ranges.
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

position_string(l::LineNumberNode) = string(l.file, ":", l.line)

"""
    bugsast_expression(expr)

Check & normalize BUGS expressions (function calls, variables, literals, indexed variables).
"""
function bugsast_expression(expr, position=LineNumberNode(1, nothing))
    if expr isa Union{Symbol,Number}
        return expr
    elseif Meta.isexpr(expr, :ref)
        return Expr(:ref, bugsast_index.(expr.args, (position,))...)
    elseif Meta.isexpr(expr, :call)
        if expr.args[1] == :getindex
            return Expr(:ref, bugsast_index.(expr.args[2:end], (position,))...)
        elseif expr.args[1] == :truncated || expr.args[1] == :censored
            if length(expr.args) == 4
                return Expr(
                    :call,
                    expr.args[1],
                    bugsast_expression.(expr.args[2:end], (position,))...,
                )
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
        stmts = [
            bugsast_statement(e, position) for e in expr.args if !(e isa LineNumberNode)
        ]
        return Expr(:block, stmts...)
    else
        try
            return Expr(:block, bugsast_statement(expr, position))
        catch
            error("Expression `$expr` at $(position_string(position)) is not a block")
        end
    end
end

check_lhs(expr) = check_lhs(Bool, expr) || error("Invalid LHS expression `$expr`")
check_lhs(::Type{Bool}, expr) = false
check_lhs(::Type{Bool}, ::Symbol) = true
function check_lhs(::Type{Bool}, expr::Expr)
    return Meta.isexpr(expr, :ref) ||
           (Meta.isexpr(expr, :call, 2) && check_lhs(Bool, expr.args[2]))
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
        return Expr(
            :if, bugsast_expression(condition, position), bugsast_block(body, position)
        )
    elseif Meta.isexpr(expr, :for, 2)
        condition, body = expr.args
        if Meta.isexpr(condition, :(=), 2)
            var = condition.args[1]
            range = bugsast_range(condition.args[2], position)
            if !(var isa Symbol)
                error(
                    "Illegal loop variable declaration at $(position_string(position)): `$condition`",
                )
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
    @bugs(expr)

Convert Julia code to an `Expr` that can be used as the AST of a BUGS program.  Checks that only
allowed syntax is used, and normalizes certain expressions.  

Used expression heads: `:~` for tilde calls, `:ref` for indexing, `:(:)` for ranges.  These are
converted from `:call` variants.
"""
macro bugs(expr)
    return Meta.quot(post_processing_expr(warn_link_function(bugsast(expr, __source__))))
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
    return Meta.quot(
        post_processing_expr(bugsast(expr, LineNumberNode(1, Symbol(@__FILE__))))
    )
end

function warn_link_function(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, f_(lhs_) = rhs_)
            error(
                "Link function syntax in BUGS is not supported with @bugsast due to conflicts with Julia syntax. 
                Please rewrite logical assignments by using the inverse of the link function on the RHS. 
                Inverse mappings are: logit => ilogit, cloglog => icloglog, log => exp, probit => phi.",
            )
        end
        return sub_expr
    end
end

function post_processing_expr(expr)
    expr = MacroTools.postwalk(expr) do sub_expr
        if sub_expr == :step
            return :_step # `step` is a Julia `Base` function
        else
            return sub_expr
        end
    end
    return cumulative(density(deviance(link_functions(expr))))
end

const INVERSE_LINK_FUNCTION = Dict(
    :logit => :logistic, :cloglog => :cexpexp, :log => :exp, :probit => :phi
)

"""
    link_functions(expr)
In case of logical assignments with the link function syntax, the statement is transformed 
to a regular assignment with the inverse link function applied to the RHS.
"""
function link_functions(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, f_(lhs_) = rhs_) # only transform logical assignments
            if f in keys(INVERSE_LINK_FUNCTION)
                sub_expr.args[1] = lhs
                sub_expr.args[2] = Expr(:call, INVERSE_LINK_FUNCTION[f], rhs)
            else
                error("Link function $f not supported.")
            end
        end
        return sub_expr
    end
end

function cumulative(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = cumulative(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :cdf
            sub_expr.args[2].args[2] = dist
            return sub_expr
        else
            return sub_expr
        end
    end
end

function density(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = density(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :pdf
            sub_expr.args[2].args[2] = dist
            return sub_expr
        else
            return sub_expr
        end
    end
end

function deviance(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, lhs_ = deviance(s1_, s2_))
            dist = find_tilde_rhs(expr, s1)
            sub_expr.args[2].args[1] = :logpdf
            sub_expr.args[2].args[2] = dist
            sub_expr.args[2] = Expr(:call, :*, -2, sub_expr.args[2])
            return sub_expr
        else
            return sub_expr
        end
    end
end

function find_tilde_rhs(expr::Expr, target::Union{Expr,Symbol})
    dist = nothing
    MacroTools.postwalk(expr) do sub_expr
        if isexpr(sub_expr, :(~))
            if sub_expr.args[1] == target
                isnothing(dist) || error("Exist two assignments to the same variable.")
                dist = sub_expr.args[2]
            end
        end
        return sub_expr
    end
    isnothing(dist) && error(
        "Error handling cumulative expression: can't find a stochastic assignment for $target.",
    )
    return dist
end

"""
    loop_fission(expr)

Fission a loop into multiple loops.

# Example
```julia-repl
julia> expr = :(
              for i = 1:10
                for j = 1:10
                     x[i, j] = i + j
                end
                y[i] = i
              end
         ); loop_fission(expr)
quote
    for i = 1:10
        for j = 1:10
            x[i, j] = i + j
        end
    end
    for i = 1:10
        y[i] = i
    end
end
```
"""
function loop_fission(expr::Expr)
    loops = loop_fission_helper(expr)
    new_expr = MacroTools.prewalk(expr) do sub_expr
        if !MacroTools.@capture(
            sub_expr,
            for loop_var_ in l_:h_
                body__
            end
        )
            return sub_expr
        end
    end
    if isnothing(new_expr)
        new_expr = Expr(:block)
    end
    filter!(x -> x !== nothing, new_expr.args)
    for l in loops
        push!(new_expr.args, generate_loop_expr(l))
    end
    return new_expr
end

function loop_fission_helper(expr::Expr)
    loops = []
    MacroTools.prewalk(expr) do sub_expr
        if MacroTools.@capture(
            sub_expr,
            for loop_var_ in l_:h_
                body__
            end
        )
            loops = []
            for ex in body
                if Meta.isexpr(ex, :for)
                    inner_loops = loop_fission_helper(ex)
                    for inner_l in inner_loops
                        push!(loops, (loop_var, l, h, inner_l))
                    end

                else
                    push!(loops, (loop_var, l, h, ex))
                end
            end
            return nothing
        end
        return sub_expr
    end
    return loops
end

function generate_loop_expr(loop)
    loop_var, l, h, remaining = loop
    if !isa(remaining, Expr)
        remaining = generate_loop_expr(remaining)
    end
    return MacroTools.prewalk(rmlines, :(
        for $loop_var in ($l):($h)
            $remaining
        end
    ))
end

function check_idxs(expr::Expr)
    return MacroTools.prewalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, x_[idxs__])
            for idx in idxs
                MacroTools.postwalk(idx) do ssub_expr
                    if Meta.isexpr(ssub_expr, :call) &&
                        !in(ssub_expr.args[1], [:+, :-, :*, :/, :(:)])
                        error("At $sub_expr: Only +, -, *, / are allowed in indexing.")
                    end
                    return ssub_expr
                end
            end
        end
        return sub_expr
    end
end

# This follow code are from early days of the parser, which uses a Julia String macro to
# transform BUGS program into Julia program
# We have since implemented a new parser, see `parser.jl`

macro _bugsmodel_str(s::String)
    # Convert and wrap the whole thing in a block for parsing
    transformed_code = "begin\n$(_bugs_to_julia(s))\nend"
    try
        expr = Meta.parse(transformed_code)
        return Meta.quot(post_processing_expr(bugsast(expr, __source__)))
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

function _bugs_to_julia(s)
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
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*T\p{Zs}*\(\p{Zs}*,(.+)\)" =>
            s"truncated(\1, nothing, \2)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*T\p{Zs}*\((.+),\p{Zs}*\)" =>
            s"truncated(\1, \2, nothing)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*T\p{Zs}*\((.+),(.+)\)" =>
            s"truncated(\1, \2, \3)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*C\p{Zs}*\(\p{Zs}*,(.+)\)" =>
            s"censored(\1, nothing, \2)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*C\p{Zs}*\((.+),\p{Zs}*\)" =>
            s"censored(\1, \2, nothing)",
        r"(var\"[^\"]+\"\([^~<=]*\))\p{Zs}*C\p{Zs}*\((.+),(.+)\)" =>
            s"censored(\1, \2, \3)",
    )

    return s
end
