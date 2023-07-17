using JuliaSyntax
using JuliaSyntax: @K_str, @KSet_str, tokenize, untokenize, Diagnostic

# the general idea is:
# 1. use `tokenize` to get the token vector
# 2. inspect tokens and build the Julia version of the program in the form of a vector of tokens
# 3. when it is appropriate to do so, just push the token to the Julia version of the program vector
# 4. at the same time, some errors are detected and diagnostics are pushed to the diagnostics vector; also some tokens may be deleted, combined, or replaced 
# 5. error recovery is very primitive: the heuristic is user forget something instead of put something wrong, a slightly more sophisticated approach is doing two versions: both "discard" and skip

mutable struct PState
    token_vec::Vector{Any}
    current_index::Int
    text::String
    julia_token_vec::Vector{Any}
    diagnostics::Vector{Diagnostic}
end
##
function PState(text::String)
    token_vec = filter(x -> kind(x) != K"error", tokenize(text))
    return PState(token_vec, 1, text, Any[], Diagnostic[])
end

function consume!(ps::PState, substitute=nothing)
    if isnothing(substitute)
        push!(ps.julia_token_vec, ps.token_vec[ps.current_index])
    else
        push!(ps.julia_token_vec, substitute)
    end
    ps.current_index += 1
end

function discard!(ps::PState)
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


function peek(ps::PState, n=1)
    if ps.current_index+n-1 > length(ps.token_vec)
        return K"EndMarker"
    end
    return kind(ps.token_vec[ps.current_index+n-1])
end

function peek_raw(ps::PState, n=1)
    if ps.current_index+n-1 > length(ps.token_vec)
        return "EOF"
    end
    return untokenize(ps.token_vec[ps.current_index+n-1], ps.text)
end

function process_trivia!(ps::PState, skip_newline=true)
    deliminators = collect(KSet"Whitespace Comment")
    if skip_newline
        push!(deliminators, K"NewlineWs")
    end
    while peek(ps) ∈ deliminators
        consume!(ps)
    end
end

function process_toplevel!(ps::PState)
    expect!(ps, "model", "begin")
    expect_and_discard!(ps, "{")
    process_statements!(ps)
    expect!(ps, "}", "end")
    process_trivia!(ps)
end

function process_statements!(ps::PState)
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

function process_assignment!(ps::PState)
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
function process_expression!(ps::PState, terminators=KSet"; NewlineWs EndMarker")
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

function process_variable!(ps::PState, allow_indexing=true)
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

function process_indexing!(ps::PState)
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

function expect!(ps::PState, expected::String, substitute=nothing)
    process_trivia!(ps)
    if peek_raw(ps) != expected
        add_diagnostic(ps, "Expecting '$expected'")
    else
        consume!(ps, substitute)
    end
end

function expect!(ps::PState, expected::Tuple, substitute=nothing)
    process_trivia!(ps)
    if peek_raw(ps) ∉ expected
        add_diagnostic(ps, "Expecting '$expected'")
    else
        consume!(ps, substitute)
    end
end

function expect_and_discard!(ps::PState, expected::String)
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

function test_on(f, str)
    ps = PState(str)
    f(ps)
    if ps.current_index > length(ps.token_vec)
        println("finished")
    else
        println("next token: $(untokenize(ps.token_vec[ps.current_index], ps.text))", )
    end
    # @show ps.julia_token_vec
    println(to_julia_program(ps.julia_token_vec, ps.text))
    io = IOBuffer()
    JuliaSyntax.show_diagnostics(io, ps.diagnostics, ps.text)
    println(String(take!(io)))
    return ps
end

function parse(prog::String)
    ps = PState(prog)
    process_toplevel!(ps)
    if !isempty(ps.diagnostics)
        io = IOBuffer()
        JuliaSyntax.show_diagnostics(io, ps.diagnostics, ps.text)
        error("Errors in the program: \n $(String(take!(io)))")
    end
    return JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, to_julia_program(ps.julia_token_vec, ps.text))
end

##
test_on(process_toplevel!, "model { } ")

test_on(process_trivia!, "  \n  a")

test_on(process_variable!, "a.b.c")
test_on(process_variable!, "x ")

test_on(process_expression!, "a.b.c + 1")

test_on(process_assignment!, "x = 1+12")

test_on(process_for!, "for (i in 1:10) { }")

test_on(process_range!, "1:10")

ps = test_on(process_assignment!, """
    alpha[i] ~ dnorm(alpha.c,alpha.tau)
""");

test_on(process_toplevel!, """model
{
   for( i in 1 : N ) {
      for( j in 1 : T ) {
         Y[i , j] ~ dnorm(mu[i , j],tau.c)
      }
      alpha[i] ~ dnorm(alpha.c,alpha.tau)
   }
}
""")

test_on(process_toplevel!, """model
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
);

test_on(process_indexing!, "[1, 2, 3]");
test_on(process_variable!, "a[1, 2, 3]");

parse("""model
{
    for i in 1 : N ) {
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
""")