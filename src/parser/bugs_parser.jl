mutable struct ProcessState
    token_vec::Vector{Token} # the tokens of the original BUGS code
    current_index::Int
    last_error_token_index::Int # stores the index of the last token that was reported as an error. This is used to ensure that the parsing process is progressing.
    text::String
    julia_token_vec::Vector{Any} # Elements can be either String or Token
    diagnostics::Vector{Diagnostic}
    replace_period::Bool
    allow_eq::Bool # allow "=" as assignment sign in original BUGS code
end

function ProcessState(text::String, replace_period=true, allow_eq=true)
    # the tokenizer will actually parsing the program string according to Julia syntax, then return the tokens
    # which means that if the program doesn't follow Julia syntax, the token stream will contain "error" tokens
    # so we remove these "error" tokens here
    token_vec = filter(x -> kind(x) != K"error", tokenize(text))
    disallowed_words = [
        t for
        t in token_vec if kind(t) ∉ WHITELIST && kind(t) ∉ JULIA_RESERVED_WORDS_W_O_FOR
    ]
    if !isempty(disallowed_words)
        diagnostics = [
            Diagnostic(
                w.range.start, w.range.stop, :error, "Unexpected token $(string(kind(w)))"
            ) for w in disallowed_words
        ]
        throw(JuliaSyntax.ParseError(JuliaSyntax.SourceFile(text), diagnostics, :none))
    end
    return ProcessState(
        token_vec, 1, 1, text, Any[], Diagnostic[], replace_period, allow_eq
    )
end

WHITELIST = KSet"Whitespace Comment NewlineWs EndMarker for in , { } ( ) [ ] : ; ~ < - <-- = + - * / ^ . Identifier Integer Float TOMBSTONE error"
# Julia reserved words are parsed to special tokens, to allow using these as variable names, we need to wrap them
# in `var"..."` to avoid syntax error in the generated Julia program
# full list of possible tokens are here: https://github.com/JuliaLang/JuliaSyntax.jl/blob/main/src/kinds.jl
JULIA_RESERVED_WORDS_W_O_FOR = KSet"baremodule begin break catch const continue do else elseif end export false finally function global if import let local macro module quote return struct true try using where while"

function ProcessState(ps::ProcessState)
    return ProcessState(
        ps.token_vec,
        ps.current_index,
        ps.last_error_token_index,
        ps.text,
        deepcopy(ps.julia_token_vec),
        deepcopy(ps.diagnostics),
        ps.replace_period,
        ps.allow_eq,
    )
end

function consume!(ps::ProcessState, substitute=nothing)
    @assert peek(ps) ∉ JULIA_RESERVED_WORDS_W_O_FOR "Julia reserved words should be wrapped in `var\"...\"` to avoid syntax error."
    if isnothing(substitute)
        push!(ps.julia_token_vec, ps.token_vec[ps.current_index])
    else
        push!(ps.julia_token_vec, substitute)
    end
    ps.current_index += 1
    return nothing
end

function discard!(ps::ProcessState)
    ps.current_index += 1
    return nothing
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

function giveup!(ps)
    # https://github.com/JuliaLang/JuliaSyntax.jl/blob/a6f2d1580f7bbad11822033e8c83e607aa31f100/src/parser_api.jl#L18
    # this only show the first parse error for now
    # even we print all the errors, current detection of errors will only allow one error per line
    throw(JuliaSyntax.ParseError(JuliaSyntax.SourceFile(ps.text), ps.diagnostics, :none))
end

function add_diagnostic!(ps, msg::String)
    return add_diagnostic!(
        ps,
        first(ps.token_vec[ps.current_index].range),
        last(ps.token_vec[ps.current_index].range),
        msg,
    )
end
function add_diagnostic!(ps, low, high, msg::String)
    # check if the current token is EOF
    if ps.current_index > length(ps.token_vec)
        diagnostic = JuliaSyntax.Diagnostic(0, 0, :error, msg)
        @assert diagnostic ∉ ps.diagnostics
        push!(ps.diagnostics, diagnostic)
        return nothing
    end
    diagnostic = JuliaSyntax.Diagnostic(low, high, :error, msg)

    if ps.current_index == ps.last_error_token_index
        push!(ps.diagnostics, diagnostic)
        giveup!(ps)
    end

    push!(ps.diagnostics, diagnostic)
    ps.last_error_token_index = ps.current_index
    return nothing
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

function last_non_trivia(ps)
    # returns either a String or a Token
    return last(
        filter(
            x -> x isa String || !(kind(x) in KSet"Whitespace Comment NewlineWs"),
            ps.julia_token_vec,
        ),
    )
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
    expect!(ps, "}", " end") # add extra white space before `end` in case of "model{}" become "beginend"
    return process_trivia!(ps)
end

function process_toplevel_no_enclosure!(ps::ProcessState)
    push!(ps.julia_token_vec, "begin ") # no newline for line number consistency
    process_statements!(ps)
    push!(ps.julia_token_vec, " end")
    return process_trivia!(ps)
end

function process_statements!(ps::ProcessState)
    process_trivia!(ps)
    while peek(ps) ∈ KSet"for Identifier" || peek(ps) ∈ JULIA_RESERVED_WORDS_W_O_FOR
        if peek(ps) == K"for"
            process_for!(ps)
        else
            # we can desugar the link function here
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
        # TODO: handle the case when the LHS is an expression
        allowed_assignment_signs = ["~", "<-"]
        if ps.allow_eq
            push!(allowed_assignment_signs, "=")
        end
        add_diagnostic!(ps, "Expecting $(join(allowed_assignment_signs, ", "))")
    end

    process_expression!(ps)
    process_trivia!(ps)
    return nothing # return to `process_statements!`
end

function process_lhs!(ps::ProcessState)
    if peek_raw(ps) ∈ ("logit", "cloglog", "log", "probit") && peek(ps, 2) != K"." # link functions
        consume!(ps) # consume the link function
        expect!(ps, "(")
        current_loc = first(ps.token_vec[ps.current_index].range)

        # test if there is more than one argument
        ps_sim = simulate(process_variable!, ps)
        if peek_next_non_trivia(ps_sim) == K","
            ps_sim = simulate(process_call_args!, ps)
            add_diagnostic!(
                ps,
                current_loc,
                last(ps_sim.token_vec[ps_sim.current_index].range) - 1,
                "Link function should be unary function, but got more than one arguments.",
            )
            giveup!(ps)
        elseif peek_next_non_trivia(ps_sim) != K")"
            ps_sim = simulate(process_call_args!, ps)
            add_diagnostic!(
                ps,
                current_loc,
                last(ps_sim.token_vec[ps_sim.current_index].range) - 1,
                "Link function argument should not be an expression.",
            )
            giveup!(ps)
        end

        # then we know it's a valid link function syntax
        process_variable!(ps)
        expect!(ps, ")")
    elseif any(Base.Fix1(startswith, peek_raw(ps)).(["logit", "cloglog", "log", "probit"])) # R-style variable names like `logit.x`
        # missing left parentheses if right parentheses is present
        ps_sim = simulate(process_variable!, ps)
        if peek(ps_sim) == K")"
            add_diagnostic!(ps, "Missing left parentheses")
        else # then it's just a variable name start with one of "logit", "cloglog", "log", "probit"
            process_variable!(ps)
        end
    else
        current_loc = first(ps.token_vec[ps.current_index].range)
        ps_copy = ProcessState(ps)
        process_variable!(ps) # might be the LHS variable or link functions that are not supported
        process_expression!(ps_copy, KSet"~ < <-- =") # might be an expression, so terminate at the assignment sign
        if peek(ps) == K"(" # un-supported link function
            link_function = last_non_trivia(ps)
            if !(link_function isa String)
                link_function = untokenize(link_function, ps.text)
            end
            add_diagnostic!(
                ps,
                current_loc,
                last(ps.token_vec[ps.current_index].range) - 1,
                "Link function `$(link_function)` is not supported",
            )

            # recovery, ideally we should also detect if the args are expressions, or if there are more than one args
            # but for now we just consume the args and the right parentheses
            process_call_args!(ps)
            expect!(ps, ")")
        elseif peek_next_non_trivia(ps) != peek_next_non_trivia(ps_copy) # LHS is an expression
            add_diagnostic!(
                ps,
                current_loc,
                last(ps_copy.token_vec[ps_copy.current_index].range) - 1,
                "LHS should be a variable, but got an expression.",
            )
            giveup!(ps)
        end
    end
    process_trivia!(ps)
    return nothing # return to `process_assignment!`
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
    expect!(ps, "}", " end") # add extra white space in case of "}}"
    return nothing # return to `process_statements!`
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
            # the tokenizer handles this well and in a intuitive way; may not be native to BUGS, but
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
                elseif peek_next_non_trivia(ps) == K"(" # blank space between function name and "("
                    add_diagnostic!(
                        ps, "Whitespace is not allowed between function name and \"(\"."
                    )
                    giveup!(ps)
                end
            end
        elseif peek(ps) ∈ JULIA_RESERVED_WORDS_W_O_FOR
            if peek(ps, 2) == K"("
                push!(ps.julia_token_vec, "var\"$(peek_raw(ps))\"") # wrap in `var"..."` to avoid syntax error
                discard!(ps) # consume the function name
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
                ps, "Expecting operator one of + - * / ^, but got $(peek_raw(ps))"
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
    if peek_next_non_trivia(ps) == K"(" && peek(ps) != K"("
        add_diagnostic!(ps, "Whitespace is not allowed between variable name and \"(\".")
    end
    expect!(ps, "(")
    process_call_args!(ps)
    expect!(ps, ")")
    process_trivia!(ps, false) # allow whitespace
    if peek_raw(ps) in ["T", "C"]
        t_or_c = peek_raw(ps)
        discard!(ps) # discard the "T" or "C"
        expect_and_discard!(ps, "(")
        push!(julia_token_vec, t_or_c == "C" ? " censored(" : " truncated(")
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
        if peek(ps) ∈ JULIA_RESERVED_WORDS_W_O_FOR
            push!(ps.julia_token_vec, "var\"$(peek_raw(ps))\"") # wrap in `var"..."` to avoid syntax error
            discard!(ps) # discard the variable name
        else
            consume!(ps)
        end
        return nothing
    end

    # deal with cases like `a.b.c` and `a.b.c[i]`
    if peek(ps, 2) == K"."
        if peek(ps, 3) != K"Identifier"
            add_diagnostic!(ps, "Variable names can't end with '.'.")
            return nothing
        end
        variable_name_buffer = String[]
        while peek(ps) == K"Identifier" || peek(ps) ∈ JULIA_RESERVED_WORDS_W_O_FOR
            if peek(ps) ∈ JULIA_RESERVED_WORDS_W_O_FOR
                push!(variable_name_buffer, "var\"$(peek_raw(ps))\"") # wrap in `var"..."` to avoid syntax error
            else
                push!(variable_name_buffer, peek_raw(ps))
            end
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
    else # cases like `a[i]` then first consume the variable name
        if peek(ps) ∈ JULIA_RESERVED_WORDS_W_O_FOR
            push!(ps.julia_token_vec, "var\"$(peek_raw(ps))\"") # wrap in `var"..."` to avoid syntax error
            discard!(ps) # discard the variable name
        else
            consume!(ps)
        end
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
        process_expression!(ps, KSet", ) EndMarker ;")

        # if ";" there will not be trivia
        if ps.julia_token_vec[end] isa Token && kind(ps.julia_token_vec[end]) == K";"
            token_range = ps.julia_token_vec[end].range
            add_diagnostic!(
                ps,
                first(token_range),
                last(token_range),
                "Calling function with keyword arguments is not supported.",
            )
            giveup!(ps)
        end

        process_trivia!(ps)
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
