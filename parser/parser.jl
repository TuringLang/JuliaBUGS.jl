

using JuliaSyntax
using JuliaSyntax: @K_str, parse!, position, bump_trivia, ParseStream, ParseState, build_tree, GreenNode, SyntaxNode, peek_token, TRIVIA_FLAG, EMPTY_FLAGS

# JuliaSyntax's tokenizer will not parse most of BUGS keyword into tokens
# use this function to do symbol comparison
function peek_symbol(ps, n=1)
    nt = JuliaSyntax.peek_full_token(ps, n)
    return Symbol(ps.textbuf[nt.first_byte:nt.last_byte])
end

function parse_and_show(production::Function, code)
    st = ParseStream(code)
    production(st)
    t = JuliaSyntax.build_tree(GreenNode, st)
    show(stdout, MIME"text/plain"(), t, code, show_trivia=true)
    if !isempty(st.diagnostics)
        println()
        for d in st.diagnostics
            JuliaSyntax.show_diagnostic(stdout, d, code)
        end
    end
    t
end

# build the parser from the bottom up

# parse atoms
ps = ParseStream("a ")
ps = PS("a.b.c + b")
ps.lookahead_index
peek(ps, 5)
peek(ps, 5)
ps.tokens
ts = []
push!(ts, "var")
push!(ts, "\"")
pos = position(ps)
ps.textbuf[pos.range_index]
push!(ts, ps.textbuf[])
emit(ps, )
bump_glue(ps, K"Identifier", EMPTY_FLAGS, 5)
build_tree(GreenNode, ps)
t = ps.tokens[2]
Symbol(ps.textbuf[1:t.next_byte-1])
peek(ps)

ps = PS("<-- b")
peek(ps)
JuliaSyntax.bump_split(ps, (1, K"<", EMPTY_FLAGS), (1, K"-", EMPTY_FLAGS), (1, K"-", EMPTY_FLAGS))
build_tree(SyntaxNode, ps)

"""
Bump several tokens, gluing them together into a single token

This is for use in special circumstances where the parser needs to resolve
lexing ambiguities. There's no special whitespace handling — bump any
whitespace if necessary with bump_trivia.
"""
function bump_glue(stream::ParseStream, kind, flags, num_tokens)
    i = stream.lookahead_index
    h = JuliaSyntax.SyntaxHead(kind, flags)
    push!(stream.tokens, JuliaSyntax.SyntaxToken(h, kind, false,
                                     stream.lookahead[i+num_tokens].next_byte))
    stream.lookahead_index += num_tokens
    stream.peek_count = 0
    return position(stream)
end

function parse_atom(st, jp)
    bump_trivia(st, skip_newlines=true)
    mark = position(st)
    k = peek(st)
    if k == K"Identifier"
        if peek(st, 2) == K"."
            
            parse_period_separated_identifier(st)
        else
            bump(st)
        end
    elseif k in (K"-", K"+") # unary minus and plus
        bump(st)
        parse_atom(st)
        emit(st, mark, K"call")
    elseif k == K"("
        bump(st, TRIVIA_FLAG)
        parse_expression(st)
        if peek(st) == K")"
            bump(st, TRIVIA_FLAG)
            # emit(st, mark, K"(")
        else
            bump_invisible(st, K"error", TRIVIA_FLAG,
                           error="Expected `)` following expression")
        end
    elseif k == K"begin"
        bump(st, TRIVIA_FLAG)
        parse_block(st, K"end", mark)
    else
        bump(st)
        emit(st, mark, K"error",
             error="Expected literal, identifier or opening parenthesis")
    end
end
    

function parse_toplevel(ps)
    mark = position(ps)
    bump_trivia(ps, skip_newlines=true)
    while true
        bump_trivia(ps, skip_newlines=true)
        if peek(ps) == K"EndMarker"
            JuliaSyntax.bump_trivia(ps; skip_newlines=true)
            break
        else
            if peek_symbol(ps) == :model
                # support model {}
                parse_model(ps)
            else # also support model definition without model keyword
                parse_stmts(ps)
            end
        end
    end
    return JuliaSyntax.emit(ps, mark, K"toplevel")
end

function parse_model(ps)
    mark = position(ps)
    if peek(ps) == K"{"
        bump(ps, JuliaSyntax.TRIVIA_FLAG;)
        parse_stmts(ps)
    else
        # emit error: require `{`
        JuliaSyntax.bump(ps; error="Expected `{`")
    end
    # parse_trailing_curly_bracket(ps)
    # emit something
    return ps
end

# BUGS allows using `;` for multiple statements on the same line and also `#` for comments
function parse_stmts(ps)
    mark = position(ps)
    return parse_Nary(ps, parse_assignment, (K";",), (K"NewlineWs",))
end

function parse_link_function(ps, allowed_functions=[])
    mark = position(ps)
    bump_trivia(ps)
    if isempty(allowed_functions) # don't check link function names    
        if peek(ps) == K"Identifier"
            bump(ps)
        else
            bump(ps, JuliaSyntax.TRIVIA_FLAG;
                 error="Expected identifier for link function") # TODO: look into emit error, keep it simple now
        end
    else
        if peek_symbol(ps) in allowed_functions
            bump(ps)
        else
            bump(ps, JuliaSyntax.TRIVIA_FLAG;
                 error="Expected link function name") # TODO: look into emit error, keep it simple now
        end
    end
    if peek(ps) == K"("
        bump(ps, JuliaSyntax.TRIVIA_FLAG)
        parse_variable_name(ps)
        if peek(ps) == K")"
            bump(ps)
            parse_assignment(ps)
        else
            bump(ps, JuliaSyntax.TRIVIA_FLAG;
                 error="Expected `)` following link function")
        end
    else
        bump(ps, JuliaSyntax.TRIVIA_FLAG;
             error="Expected `(` following link function") 
    end
end

function parse_variable_name(ps)
    mark = position(ps)
    bump_trivia(ps)
    # need to handle R style variable names, i.e. `a.b`
   
    if peek(ps) == K"["
        # bump
        # parse range (may contain `,`)
        if peek(ps) == K"]"
            # bump
        else
            # error
        end
    else
        parse_period_separated_identifier(ps)
    end
end

function parse_period_separated_identifier(ps)
    # similar to Nary, but don't bump until whitespace or newline
    mark = position(ps)
    bump_trivia(ps)
    k = peek(ps)

    #TODO: first check "." not the first character, not necessary, because the tokenizer handles it

    if k == K"EndMarker" || k == K"NewlineWs" || k == K")"
        return nothing
    end
    name_buffer = []
    k = peek(ps)
    n_pieces = 0
    while peek(ps) != K"EndMarker" && peek(ps) != K"NewlineWs"
        if k == K"Identifer"
            push!(name_buffer, peek_symbol(ps))
            n_pieces += 1
        elseif l == K"."

        end
    end
    # customized bumping
    # TODO: figure out how to add var"", also need to skip the correct number of bytes
end

prog = "#some comment\n a.b.c"
ps = ParseStream(prog)
bump_trivia(ps)
dump(ps)
ps.lookahead_index    

function parse_assignment(ps) 
    mark = position(ps)
    bump_trivia(ps)
    k = peek(ps)
    if k == K"<" 
        if peek(ps, 2) == K"-"
            # TODO: replace with K"="
            # TODO: do some skipping and byte management
            parse_expression(ps)
        else
            bump(ps, JuliaSyntax.TRIVIA_FLAG;
                 error="Expected `<-`")
        end
    elseif k == K"<--"
        # TODO: find a way to break this into two tokens
        # work out the `seek` and all that
        # TODO: probably need to work with Lexer
    elseif k == K"~"
        parse_distributions(ps)
    else
        bump(ps, JuliaSyntax.TRIVIA_FLAG;
             error="Expected `<-` or `~`")
    end
end

ps = ParseStream("var\"a.b\"")
parse!(ps)
ps.tokens
tokenize("var\"a.b\"")

untokenize(tokenize("var\"a.b\"")[3], "var\"a.b\"")

function parse_expression(ps)
    # parse expression on the RHS of logical assignment
    # end with ;
    # TODO: just reuse Julia's parser for this part
end

function parse_Nary(ps, down, delimiters, closing_tokens)
    bump_trivia(ps)
    k = peek(ps)
    if k in closing_tokens
        return nothing
    end
    n_delims = 0
    if k in delimiters
        # allow leading delimiters
        # ; a  ==>  (block a)
    else
        # a ; b  ==>  (block a b)
        down(ps)
    end
    while peek(ps) in delimiters
        bump(ps, JuliaSyntax.TRIVIA_FLAG)
        n_delims += 1
        k = peek(ps)
        if k == K"EndMarker" || k in closing_tokens
            break
        elseif k in delimiters
            # ignore empty delimited sections
            # a;;;b  ==>  (block a b)
            continue
        end
        down(ps)
    end
    return n_delims != 0
end
