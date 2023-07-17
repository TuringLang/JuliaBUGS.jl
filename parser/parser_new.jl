using JuliaSyntax
using JuliaSyntax: tokenize, Diagnostic, kind




# copy trivia tokens to Julia program
function skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    while kind(token_vec[current_index]) == K"NewlineWs" || kind(token_vec[current_index]) == K"Comment" || kind(token_vec[current_index]) == K"Whitespace"
        push!(julia_token_vec, token_vec[current_index]) # copy the current token
        current_index += 1
    end
    return current_index
end

function process_toplevel!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    kind(token_vec[current_index]) == K"EndMarker" && return nothing
    if untokenize(token_vec[1], text) == "model"
        current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
        kind(token_vec[current_index]) == K"EndMarker" && return nothing
        if kind(token_vec[current_index]) == K"{"
            push!(julia_token_vec, K"begin")
            current_index += 1
        else
            push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `{`"))
        end
        current_index = process_bcurrent_indexk!(token_vec, current_index, text, julia_token_vec, diagnostics)
    else # also accept program without `model` keyword
        current_index = process_bcurrent_indexk!(token_vec, current_index, text, julia_token_vec, diagnostics)
    end
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    if peek_kind(token_vec, current_index) == K"EndMarker"
        push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `}`"))
        push!(julia_token_vec, K"end")
    end
    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K"}", true, K"end")
    skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    if peek_kind(token_vec, current_index) != K"EndMarker"
        push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Program outside of `model` bcurrent_indexk"))
    end
end



function process_bcurrent_indexk!(token_vec, current_index, text, julia_token_vec, diagnostics)
    while kind(token_vec[current_index]) != K"EndMarker" && kind(token_vec[current_index]) != K"}"
        current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
        if kind(token_vec[current_index]) == K"Identifier"
            current_index = process_assignment!(token_vec, current_index, text, julia_token_vec, diagnostics)
        elseif kind(token_vec[current_index]) == K"for"
            current_index = process_for!(token_vec, current_index, text, julia_token_vec, diagnostics)
        else
            # we won't implement back tracking for more complicated error recovery
            @error "in function `process_bcurrent_indexk!`, unexpected token: $k"
        end
    end
    return current_index
end

function process_for!(token_vec, current_index, text, julia_token_vec, diagnostics)
    push!(julia_token_vec, token_vec[current_index]) # just "for"
    current_index += 1
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    # TODO: check against newline, because it delimits expressions
    
    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K"(", false)
    current_index = process_for_cond!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K")", false)

    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K"{", false)
    current_index = process_bcurrent_indexk!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K"}", true, K"end")
    return current_index
end


function expect!(token_vec, current_index, text, julia_token_vec, diagnostics, expected, copy, sub=nothing)
    if kind(token_vec[current_index]) == expected || kind(token_vec[current_index]) in expected
        if copy
            if isnothing(sub)
                push!(julia_token_vec, token_vec[current_index])
            else
                push!(julia_token_vec, sub)
            end
        end
        current_index += 1
    else
        push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `$expected`"))
    end
    return current_index
end

function process_for_cond!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    kind(token_vec[current_index]) != K"Identifier" && push!(diagnostics, Diagnostics(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `loop variable`"))
    current_index = process_variable_name!(token_vec, current_index, text, julia_token_vec, diagnostics)

    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K"in", true)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)

    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K"Integer", true)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K":", true)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K"Integer", true)

    return current_index
end

function process_variable_name!(token_vec, current_index, text, julia_token_vec, diagnostics)
    var_name = ""
    if current_index == length(token_vec)
        push!(js, token_vec[current_index])
        current_index += 1
        return current_index
    end
    while kind(head(token_vec[current_index])) == K"Identifier" && kind(head(token_vec[current_index+1])) == K"."
        var_name *= untokenize(token_vec[current_index], text) * untokenize(token_vec[current_index+1], text)
        current_index += 2
        if current_index == length(token_vec)
            push!(js, token_vec[current_index])
            current_index += 1
            return current_index
        end
    end
    if var_name != "" 
        if kind(head(token_vec[current_index])) == K"Identifier"
            var_name *= untokenize(token_vec[current_index], text)
            current_index += 1
        else
            push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `variable name`"))
        end
    else
        var_name = untokenize(token_vec[current_index], text)
        current_index += 1
    end
    push!(julia_token_vec, K"var", K"\"", var_name, K"\"")
    if current_index <= length(token_vec) && kind(token_vec[current_index]) == K"["
        push!(julia_token_vec, token_vec[current_index])
        current_index = process_indices!(token_vec, current_index+1, text, julia_token_vec, diagnostics)
        current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K"]", true)
    end
    return current_index
end

# example tokenize("[1, 1:2, ]" white space before ] or , is special case, add ":" to the output
function process_indices!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    if kind(token_vec[current_index]) == K"]"
        return current_index
    end
    while kind(token_vec[current_index]) != K"]"
        current_index = process_expression!(token_vec, current_index, text, julia_token_vec, diagnostics)
        current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
        if kind(token_vec[current_index]) == K"]"
            push!(julia_token_vec, ":")
            return current_index
        elseif kind(token_vec[current_index]) == K","
            push!(julia_token_vec, token_vec[current_index])
            current_index += 1
            current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
        else
            push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `,` or `]`"))
        end
    end
    return current_index
end

function process_expressions!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = process_single_op!(token_vec, current_index, text, julia_token_vec, diagnostics, [K"+", K"-"]) # check for unary + and -
    k = kind(token_vec[current_index])
    if k != K"Identifier" && k != K"Integer" && k != K"Float" && k != K"("
        push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `expression`"))
    end
    # TODO: deal with brackets
    while !(k == K"}" || k == K";" || k == K"NewlineWs" || k == K",")
        current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
        current_index = process_single_term!(token_vec, current_index, text, julia_token_vec, diagnostics)
        current_index = process_single_op!(token_vec, current_index, text, julia_token_vec, diagnostics, [K"+", K"-", K"*", K"/"])
        k = kind(token_vec[current_index])
    end
    return current_index
end

function process_single_term!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index == length(token_vec) && return current_index
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    k = kind(token_vec[current_index])
    if k == K"Integer" || k == K"Float"
        push!(julia_token_vec, token_vec[current_index])
        current_index += 1
        return current_index
    end
    if k == K"Identifier"
        current_index = process_variable_name!(token_vec, current_index, text, julia_token_vec, diagnostics)
        current_index == length(token_vec) && return current_index
        if kind(token_vec[current_index+1]) == K"("
            current_index = process_call_args!(token_vec, current_index, text, julia_token_vec, diagnostics)
            current_index = expect!(token_vec, current_index, text, julia_token_vec, diagnostics, K")", true)
        end
    else
        push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `variable name` or `function call`"))
    end
    return current_index
end

function process_call_args!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    if kind(token_vec[current_index]) == K")"
        return current_index
    end
    while kind(token_vec[current_index]) != K")"
        current_index = process_expression!(token_vec, current_index, text, julia_token_vec, diagnostics)
        current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
        if kind(token_vec[current_index]) == K")"
            return current_index
        elseif kind(token_vec[current_index]) == K","
            push!(julia_token_vec, token_vec[current_index])
            current_index += 1
            current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
        else
            push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `,` or `)`"))
        end
    end
    return current_index
end

function process_single_op!(token_vec, current_index, text, julia_token_vec, diagnostics, ops)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    if kind(token_vec[current_index]) in ops
        push!(julia_token_vec, token_vec[current_index])
        current_index += 1
    end
    return current_index
end

function process_assign_sign!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    if kind(token_vec[current_index]) == K"<"
        current_index == length(token_vec) && return current_index
        if kind(token_vec[current_index+1]) == K"-"
            push!(julia_token_vec, K"=")
            current_index += 2
        else
            push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `<-`"))
        end
    else # k == K"<--"
        push!(julia_token_vec, K"=")
        current_index += 1
        current_index = process_single_op!(token_vec, current_index, text, julia_token_vec, diagnostics, [K"-"])
    end
    return current_index
end

function process_assignment!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = process_single_term!(token_vec, current_index, text, julia_token_vec, diagnostics)
    current_index = skip_trivia!(token_vec, current_index, text, julia_token_vec, diagnostics)
    if kind(token_vec[current_index]) == K"<" || kind(token_vec[current_index]) == K"<--"
        current_index = process_assign_sign!(token_vec, current_index, text, julia_token_vec, diagnostics)
    elseif kind(token_vec[current_index]) == K"~"
        push!(julia_token_vec, K"=")
        current_index += 1
    else
        push!(diagnostics, Diagnostic(token_vec[current_index].range.start, token_vec[current_index].range.stop, :error, "Expected `<-` or `~`"))
    end
    current_index = process_expressions!(token_vec, current_index, text, julia_token_vec, diagnostics)
    return current_index
end
