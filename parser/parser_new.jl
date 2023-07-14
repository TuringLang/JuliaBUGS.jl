using JuliaSyntax
using JuliaSyntax: tokenize, Diagnostic, head, kind

prog = """model
{
   for( i in 1 : N ) {
      for( j in 1 : T ) {
         Y[i , j] ~ dnorm(mu[i , j],tau.c)
         mu[i , j] <- alpha[i] + beta[i] * (x[j] - xbar)
      }
      alpha[i] ~ dnorm(alpha.c,alpha.tau)
      beta[i] ~ dnorm(beta.c,beta.tau)
   }
   tau.c ~ dgamma(0.001,0.001)
   sigma <- 1 / sqrt(tau.c)
   alpha.c ~ dnorm(0.0,1.0E-6)   
   alpha.tau ~ dgamma(0.001,0.001)
   beta.c ~ dnorm(0.0,1.0E-6)
   beta.tau ~ dgamma(0.001,0.001)
   alpha0 <- alpha.c - xbar * beta.c   
}
"""

tv = tokenize(prog)

# the general idea is:
# 1. use `tokenize` to get the token vector
# 2. inspect tokens and build the Julia version of the program in the form of a vector of tokens
# 3. when it is appropriate to do so, just push the token to the Julia version of the program vector
# 4. at the same time, some errors are detected and diagnostics are pushed to the diagnostics vector; also some tokens may be deleted, combined, or replaced 

function process_toplevel(tv, loc, text, jp, diagnostics)
    if untokenize(tv[1]) == "model"
        loc = skip_trivia!(tv, loc, jp, text, diagnostics)
        k = kind(tv[loc])
        if k != K"{"
            push!(diagnostics, Diagnostics(tv[loc].range.start, tv[loc].range.stop, :error, "Expected `{`"))
        end
        process_block!(tv, loc, text, jp, diagnostics)
    else
        # assume not wrapped in model{}
        process_block!(tv, loc, text, jp, diagnostics)
    end
end

function skip_trivia!(tv, loc, text, jp, diagnostics)
    k = kind(tv[loc])
    while k == K"Whitespace" || k == K"Comment" || k == K"NewlineWs"
        push!(jp, tv[loc])
        loc += 1
    end
    return loc
end

function process_block!(tv, loc, text, jp, diagnostics)
    k = kind(tv[loc])
    while k != K"EndMarker" && k != K"}"
        loc = skip_trivia!(tv, loc, text, jp, diagnostics)
        k = kind(tv[loc])
        if k == K"Identifer"
            loc = process_assignment!(tv, loc, text, jp, diagnostics)
        elseif k == K"for"
            loc = process_for!(tv, loc, text, jp, diagnostics)
        else
            # we won't implement back tracking for more complicated error recovery
            @error "in function `process_block!`, unexpected token: $k"
        end
    end
    return loc
end

function emit_diagnostic(stream::ParseStream, byterange::AbstractUnitRange; kws...)
    emit_diagnostic(stream.diagnostics, byterange; kws...)
    return nothing
end

function process_for!(tv, loc, text, jp, diagnostics)
    push!(jp, tv[loc]) # just "for"
    loc += 1
    loc = skip_trivia!(tv, loc, text, jp, diagnostics)
    # TODO: check against newline, because it delimits expressions
    
    loc = expect!(tv, loc, text, jp, diagnostics, K"(", false)
    loc = process_for_cond!(tv, loc, text, jp, diagnostics)
    loc = expect!(tv, loc, text, jp, diagnostics, K")", false)

    loc = expect!(tv, loc, text, jp, diagnostics, K"{", false)
    loc = process_block!(tv, loc, text, jp, diagnostics)
    loc = expect!(tv, loc, text, jp, diagnostics, K"}", true, K"end")
    return loc
end

function expect!(tv, loc, text, jp, diagnostics, expected, copy, sub=nothing)
    k = kind(tv[loc])
    if k == expected
        if copy
            if isnothing(sub)
                push!(jp, tv[loc])
            else
                push!(jp, sub)
            end
        end
        loc += 1
    else
        push!(diagnostics, Diagnostic(tv[loc].range.start, tv[loc].range.stop, :error, "Expected `$expected`"))
    end
    return loc
end

function process_for_cond!(tv, loc, text, jp, diagnostics)
    loc = skip_trivia!(tv, loc, text, jp, diagnostics)
    k = kind(tv[loc])
    k != K"Identifier" && push!(diagnostics, Diagnostics(tv[loc].range.start, tv[loc].range.stop, :error, "Expected `loop variable`"))
    loc = process_variable_name!(tv, loc, text, jp, diagnostics)

    loc = skip_trivia!(tv, loc, text, jp, diagnostics)
    loc = expect!(tv, loc, text, jp, diagnostics, K"in", true)
    loc = skip_trivia!(tv, loc, text, jp, diagnostics)

    loc = expect!(tv, loc, text, jp, diagnostics, K"Integer", true)
    loc = skip_trivia!(tv, loc, text, jp, diagnostics)
    loc = expect!(tv, loc, text, jp, diagnostics, K":", true)
    loc = skip_trivia!(tv, loc, text, jp, diagnostics)
    loc = expect!(tv, loc, text, jp, diagnostics, K"Integer", true)

    return loc
end



function process_variable_name!(tv, loc, text, jp, diagnostics)
    var_name = ""
    while kind(head(tv[loc])) == K"Identifier" && kind(head(tv[loc+1])) == K"."
        var_name *= untokenize(tv[loc], text) * untokenize(tv[loc+1], text)
        loc += 2
    end
    if var_name != "" 
        if kind(head(tv[loc])) == K"Identifier"
            var_name *= untokenize(tv[loc], text)
            loc += 1
        else
            push!(diagnostics, Diagnostic(tv[loc].range.start, tv[loc].range.stop, :error, "Expected `variable name`"))
        end
    else
        var_name = untokenize(tv[loc], text)
        loc += 1
    end
    push!(jp, K"var", K"\"", var_name, K"\"")
    if loc <= length(tv) && kind(tv[loc]) == K"["
        push!(jp, tv[loc])
        loc = process_indices!(tv, loc+1, text, jp, diagnostics)
        loc = expect!(tv, loc, text, jp, diagnostics, K"]", true)
    end
    return loc
end

# example tokenize("[1, 1:2, ]" white space before ] or , is special case, add ":" to the output
function process_indices!(tv, loc, text, jp, diagnostics)
    loc = skip_trivia!(tv, loc, text, jp, diagnostics)
    k = kind(tv[loc])
    if k == K"]"
        return loc
    end
    while k != K"]"
        loc = process_expression!(tv, loc, text, jp, diagnostics)
        loc = skip_trivia!(tv, loc, text, jp, diagnostics)
        k = kind(tv[loc])
        if k == K"]"
            push!(jp, ":")
            return loc
        elseif k == K","
            push!(jp, tv[loc])
            loc += 1
            loc = skip_trivia!(tv, loc, text, jp, diagnostics)
            k = kind(tv[loc])
        else
            push!(diagnostics, Diagnostic(tv[loc].range.start, tv[loc].range.stop, :error, "Expected `,` or `]`"))
        end
    end
    return loc
end

# expressions are delimited by ";" or "\n"" or "," or "}"
function process_expressions!(tv, loc, text, jp, diagnostics)

end

function process_assignment!(tv, loc, text, jp, diagnostics)
    
end

