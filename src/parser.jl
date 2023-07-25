using JuliaSyntax
using JuliaSyntax: @K_str, @KSet_str, tokenize, untokenize, Diagnostic
using JuliaFormatter

# called `ProcessState` instead of `ParseState` because it's not really "parsing"
mutable struct ProcessState
    token_vec::Vector{JuliaSyntax.Token}
    current_index::Int
    text::String
    julia_token_vec::Vector{Any}
    diagnostics::Vector{Diagnostic}
    replace_period::Bool
    allow_eq::Bool
end
##

function ProcessState(text::String, replace_period=true, allow_eq=true)
    token_vec = filter(x -> kind(x) != K"error", tokenize(text))
    return ProcessState(token_vec, 1, text, Any[], Diagnostic[], replace_period, allow_eq)
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

function add_diagnostic(ps, msg::String)
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
    if diagnostic in ps.diagnostics # TODO: this check may be too expensive
        error("Encounter duplicate diagnostic, suspect infinite loop, stop and fix first.")
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

function peek_non_trivia(ps::ProcessState, skip_newline=true)
    trivia_tokens = KSet"Whitespace Comment"
    skip_newline && (trivia_tokens = trivia_tokens ∪ KSet"NewlineWs")

    # Save the current state
    saved_index = ps.current_index

    # Skip over trivia
    while kind(ps.token_vec[saved_index]) ∈ trivia_tokens
        saved_index += 1
        if saved_index > length(ps.token_vec)
            return K"EndMarker"
        end
    end

    # Return the kind of the next non-trivia token
    return kind(ps.token_vec[saved_index])
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
    expect!(ps, "}", "end")
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
    process_variable!(ps)
    if peek(ps) == K"(" # link function
        consume!(ps) # consume the "("
        process_trivia!(ps)
        process_variable!(ps) # link functions can only take one argument
        process_trivia!(ps)
        expect!(ps, ")")
    end
    process_trivia!(ps)

    if peek(ps) == K"~"
        consume!(ps)
        process_tilde_rhs!(ps)
        process_trivia!(ps)
        return nothing
    end

    if ps.allow_eq && peek(ps) == K"="
        consume!(ps)
    elseif peek(ps) == K"<" && peek(ps, 2) == K"-"
        discard!(ps)
        discard!(ps)
        push!(ps.julia_token_vec, "=")
    elseif peek(ps) == K"<--"
        discard!(ps)
        push!(ps.julia_token_vec, "=")
        push!(ps.julia_token_vec, "-")
        process_identifier_led_expression!(ps)
    else
        allowed_assignment_signs = ["~", "<-"]
        if ps.allow_eq
            push!(allowed_assignment_signs, "=")
        end
        add_diagnostic(ps, "Expecting $(join(allowed_assignment_signs, ", "))")
    end

    process_expression!(ps)
    return process_trivia!(ps)
end

function process_for!(ps)
    consume!(ps) # consume the "for"
    expect_and_discard!(ps, "(")
    if peek(ps) == K"Identifier"
        push!(ps.julia_token_vec, " ")
    end

    process_variable!(ps)
    expect!(ps, "in")
    process_range!(ps)
    expect_and_discard!(ps, ")")

    expect_and_discard!(ps, "{")
    process_statements!(ps)
    return expect!(ps, "}", "end")
end

function process_range!(ps)
    process_expression!(ps, KSet": , ]")
    expect!(ps, ":")
    return process_expression!(ps, KSet")")
end

function process_expression!(
    ps::ProcessState, terminators=KSet"; NewlineWs EndMarker } for"
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
                    process_call_args!(ps)
                    expect!(ps, ")")
                end
            end
        elseif peek(ps) == K"("
            consume!(ps)
            process_expression!(ps, KSet")")
            expect!(ps, ")")
        else
            add_diagnostic(ps, "Expecting variable or parenthesized expressions")
        end
        process_trivia!(ps, false)
        if peek(ps) ∈ terminators
            if peek(ps) == K";" # others will be consumed by process_trivia!
                consume!(ps)
            elseif peek(ps) == K"for" # in case of `for(i in 1:10)`, otherwise `fori ...`
                push!(ps.julia_token_vec, "\n")
            end
            return nothing
        end
        expect!(ps, ("+", "-", "*", "/", "^"))
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
    if peek_raw(ps) in ["T", "C"]
        discard!(ps)
        expect_and_discard!(ps, "(")
        push!(julia_token_vec, peek_raw(ps) == "C" ? " censored(" : " truncated(")
        push!(julia_token_vec, buffer..., ", ")
        ps.julia_token_vec = julia_token_vec
        if peek_non_trivia(ps) == K","
            push!(julia_token_vec, "nothing")
        else
            process_expression!(ps, KSet",")
        end
        expect!(ps, ",")
        if peek_non_trivia(ps) == K")"
            push!(ps.julia_token_vec, "nothing")
        else
            process_expression!(ps, KSet")")
        end
        expect!(ps, ")")
    else
        push!(julia_token_vec, buffer...)
        ps.julia_token_vec = julia_token_vec
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

function expect!(ps::ProcessState, expected::String, substitute=nothing)
    process_trivia!(ps)
    if peek_raw(ps) != expected
        add_diagnostic(ps, "Expecting '$expected'")
    else
        consume!(ps, substitute)
    end
end

function expect!(ps::ProcessState, expected::Tuple, substitute=nothing)
    process_trivia!(ps)
    if peek_raw(ps) ∉ expected
        add_diagnostic(ps, "Expecting '$expected'")
    else
        consume!(ps, substitute)
    end
end

function expect_and_discard!(ps::ProcessState, expected::String)
    process_trivia!(ps)
    if peek_raw(ps) != expected
        add_diagnostic(ps, "Expecting '$expected'")
    else
        discard!(ps)
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

function parse(prog::String, replace_period=true, format_output=true)
    ps = ProcessState(prog, replace_period)
    process_toplevel!(ps)
    if !isempty(ps.diagnostics)
        io = IOBuffer()
        JuliaSyntax.show_diagnostics(io, ps.diagnostics, ps.text)
        error("Errors in the program: \n $(String(take!(io)))")
    end
    # return JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, to_julia_program(ps.julia_token_vec, ps.text))
    julia_program = to_julia_program(ps.julia_token_vec, ps.text)
    format_output && (julia_program = format_text(julia_program))
    return println(julia_program)
end