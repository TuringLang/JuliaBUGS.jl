using JuliaSyntax
using JuliaSyntax: @K_str, @KSet_str, tokenize, untokenize, Diagnostic

# called `ProcessState` instead of `ParseState` because it's not really "parsing"
mutable struct ProcessState
    token_vec::Vector{Any}
    current_index::Int
    text::String
    julia_token_vec::Vector{Any}
    diagnostics::Vector{Diagnostic}
end

function ProcessState(text::String)
    token_vec = filter(x -> kind(x) != K"error", tokenize(text))
    return ProcessState(token_vec, 1, text, Any[], Diagnostic[])
end

function consume!(ps::ProcessState, substitute=nothing)
    if isnothing(substitute)
        push!(ps.julia_token_vec, ps.token_vec[ps.current_index])
    else
        push!(ps.julia_token_vec, substitute)
    end
    ps.current_index += 1
end

function discard!(ps::ProcessState)
    ps.current_index += 1
end

function add_diagnostic(ps, msg::String)
    # check if the current token is EOF
    if ps.current_index > length(ps.token_vec)
        diagnostic = JuliaSyntax.Diagnostic(0, 0, :error, msg)
        @assert diagnostic ∉ ps.diagnostics
        push!(ps.diagnostics, diagnostic)
        return
    end
    low = first(ps.token_vec[ps.current_index].range)
    high = last(ps.token_vec[ps.current_index].range)
    diagnostic = JuliaSyntax.Diagnostic(low, high, :error, msg)
    if diagnostic in ps.diagnostics # TODO: this check may be too expensive
        error("Encounter duplicate diagnostic, suspect infinite loop, stop and fix first.")
    end
    push!(ps.diagnostics, diagnostic)
end

function peek(ps::ProcessState, n=1)
    if ps.current_index+n-1 > length(ps.token_vec)
        return K"EndMarker"
    end
    return kind(ps.token_vec[ps.current_index+n-1])
end

function peek_raw(ps::ProcessState, n=1)
    if ps.current_index+n-1 > length(ps.token_vec)
        return "EOF"
    end
    return untokenize(ps.token_vec[ps.current_index+n-1], ps.text)
end

function process_trivia!(ps::ProcessState, skip_newline=true)
    deliminators = collect(KSet"Whitespace Comment")
    if skip_newline
        push!(deliminators, K"NewlineWs")
    end
    while peek(ps) ∈ deliminators
        consume!(ps)
    end
end

function process_toplevel!(ps::ProcessState)
    expect!(ps, "model", "begin")
    expect_and_discard!(ps, "{")
    process_statements!(ps)
    expect!(ps, "}", "end")
    process_trivia!(ps)
end

function process_statements!(ps::ProcessState)
    process_trivia!(ps)
    while true
        if peek(ps) == K"for"
            process_for!(ps)
        elseif peek(ps) == K"Identifier"
            process_assignment!(ps)
        else
            break
        end
        process_trivia!(ps, )
    end
end

function process_assignment!(ps::ProcessState)
    process_variable!(ps)
    process_trivia!(ps)
    if peek(ps) == K"<--"
        discard!(ps)
        push!(ps.julia_token_vec, "=")
        push!(ps.julia_token_vec, "-")
        process_identifier_led_expression!(ps)
        return
    end

    if peek(ps) == K"~"
        consume!(ps)
    elseif peek(ps) == K"<"
        if peek(ps, 2) == K"-"
            discard!(ps)
            discard!(ps)
            push!(ps.julia_token_vec, "=")
        else
            add_diagnostic(ps, "Expecting <-")
        end
    else
        add_diagnostic(ps, "Expecting <- or ~")
    end
    process_expression!(ps)
    process_trivia!(ps) # consume newline or ;
end

function process_for!(ps)
    consume!(ps) # consume the "for"
    expect_and_discard!(ps, "(")

    process_variable!(ps)
    expect!(ps, "in")
    process_range!(ps)
    expect_and_discard!(ps, ")")

    expect_and_discard!(ps, "{")
    process_statements!(ps)
    expect!(ps, "}", "end")
end

function process_range!(ps)
    expect_and_process_atom!(ps)
    expect!(ps, ":")
    expect_and_process_atom!(ps)
end

# numerals or variables
function expect_and_process_atom!(ps)
    process_trivia!(ps)
    if peek(ps) ∈ KSet"Integer Float"
        consume!(ps)
    elseif peek(ps) == K"Identifier"
        process_variable!(ps, false)
    else
        add_diagnostic(ps, "Loop bounds must be numerals or variables")
    end
end
# sub cases
# unary +, -
# function call: f(x+z, y)
# variable: x, a.b
function process_expression!(ps::ProcessState, terminators=KSet"; NewlineWs EndMarker")
    process_trivia!(ps)
    if peek(ps) ∈ KSet"+ -" # only allow a single + or - at the beginning
        consume!(ps)
    end
    process_identifier_led_expression!(ps, terminators)
end

function process_identifier_led_expression!(ps, terminators=KSet"; NewlineWs EndMarker")
    process_trivia!(ps)
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
            end
            return
        end
        expect!(ps, ("+", "-", "*", "/", "^"))
        process_trivia!(ps)
    end
end

function process_variable!(ps::ProcessState, allow_indexing=true)
    process_trivia!(ps)

    if peek(ps, 2) ∉ KSet". ["
        consume!(ps)
        return
    end

    if peek(ps, 2) == K"."
        variable_name_buffer = String[]
        while peek(ps) == K"Identifier"
            push!(variable_name_buffer, peek_raw(ps))
            discard!(ps)
            if peek(ps) != K"."
                break
            end
            push!(variable_name_buffer, ".")
            discard!(ps)
        end

        push!(ps.julia_token_vec, "var\"$(join(variable_name_buffer, ""))\"")
    else
        consume!(ps)
    end

    if !allow_indexing
        return
    end

    if peek(ps) == K"["
        process_indexing!(ps)
    end
end

function process_indexing!(ps::ProcessState)
    expect!(ps, "[")
    process_trivia!(ps)
    while peek_raw(ps) != "," && peek(ps) != "EndMarker"
        process_index!(ps)
        process_trivia!(ps)
        if peek_raw(ps) != ","
            break
        end
        expect!(ps, ",")
        process_trivia!(ps)
    end
    expect!(ps, "]")
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

function parse(prog::String)
    ps = ProcessState(prog)
    process_toplevel!(ps)
    if !isempty(ps.diagnostics)
        io = IOBuffer()
        JuliaSyntax.show_diagnostics(io, ps.diagnostics, ps.text)
        error("Errors in the program: \n $(String(take!(io)))")
    end
    return JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, to_julia_program(ps.julia_token_vec, ps.text))
end
