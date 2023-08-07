The BUGS parser implemented here takes a token stream with a recursive descent structure and checks the correctness of the program. 

The general idea is:
1. use `tokenize` to get the token vector
2. inspect tokens and build the Julia version of the program in the form of a vector of tokens
3. when it is appropriate to do so, push the token to the Julia version of the program vector
4. at the same time, some errors are detected, and diagnostics are pushed to the diagnostics vector; also, some tokens may be deleted, combined, or replaced 

More concretely, in the process of the recursive descent, BUGS syntax tokens will be translated into Julia syntax tokens. 
The tokens that are already compatible with Julia will remain. Others will be either transformed or removed. Also, additional tokens may be added.

The parser will throw an error given a program not in strict BUGS syntax.

**NOTE**: Strictly speaking, the program is not "parsing" because the program doesn't output a syntax tree. 

## Some Notes on error recovery
The current error recovery is ad hoc and mostly primitive.
The parser is written so that if the program is correct, the program will descend into the correct function, thus producing the correct result. If the program is not correct, the wavefront of the token stream will not be pushed forward. Thus, it will fail. 
One of the failure detection mechanism is to check if two error occurs with the same "current token". If there are, then the parser will stop and report the error. This is reassuring in the sense that the parser will not parse wrong programs. 
(Maybe instead of giving up, we can enter the recovery(panic) mode, find a rendezvous(synchronization) point, and continue parsing. This is not straightforward because sometimes we are in a deep call stack. The most straightforward way to implement using exception handling

```julia
struct ParseException <: Exception end

function parse_expression(parser::Parser)
    # parsing code here
    # If an error occurs, throw ParseException()
end

function parse_statement(parser::Parser)
    # parsing code here
    # If an error occurs, throw ParseException()
end

# ... more parsing functions ...

function parse_program(parser::Parser)
    while !eof(parser)
        try
            parse_statement(parser)
        catch e
            if isa(e, ParseException)
                # Handle the error and recover
                # This might involve advancing to a synchronization point in the input
            else
                rethrow(e)  # If it's not a ParseException, re-throw it
            end
        end
    end
end
```
credit ChatGPT for the example code.)

Panic mode is a last resort. Ideally, we want to try to sync up the parsing state and continue parsing. Some thoughts:
* Singular error
    * Misspell
        * The misspelled word is parsed into a single token
            * The right thing to do is record the diagnostic and discard and continue parsing
            * Reliable detection is difficult, especially since misspelled words can be parsed into multiple tokens, so simply checking the next token is not enough, but it might be a good enough heuristic
        * The misspelled word is parsed into multiple tokens
            * The right thing, in this case, is to skip all the tokens birthed by the misspelled word and continue parsing
            * This might not be that bad because we whitelist the tokens that can be parsed into multiple tokens
    * Missing
        * the right thing to do is just continue without consuming or discarding
    * Extra
        * the right thing is to discard until the start of the next state
* Consecutive errors
    * This can be tricky because the detection is very difficult in the worst case. If we have a state syncing function for every state, and the lookahead length is 2, then we can match the "next token" enter the next state, and then try to sync again in that state.

Cases we can handle by matching

The difficulty comes from the fact that the tokenizer is not built for BUGS.

Some starting code
```julia
function sync_state(ps::ProcessState, current_token::String, next_token::Tuple)
    if peek_raw(ps) == current_token && peek_raw(ps, 2) in next_token
        return nothing
    elseif peek_raw(ps) == current_token ## peek_raw(ps, 2) != next_token
        # start an error diagnostic
        # then we seek till one of the next_token is found
        # if not found anything in the given budget, add to the diagnostic
        # add a special place_holder and move on
    elseif peek_raw(ps, 2) == next_token # peek_raw(ps) != current_token
    else
    end
end

function skip_until(ps::ProcessState, t::String, depth_limit=5)
    seek_index = ps.current_index
    while untokenize(ps.token_vec[seek_index], ps.text) != t
        seek_index += 1
        if seek_index > length(ps.token_vec)
            return length(ps.token_vec)
        end
        if seek_index - ps.current_index > depth_limit
            return nothing # give up, indicate that the token is probably missing
        end
    end
    return seek_index # maybe the actual location in the text 
end
```

More prototype code on a later try
```julia
function discard_until!(ps::ProcessState, targets::Vector{String})
    discarded_program_piece = ""
    text_pos_pre = peek(ps).range.start
    while peek_raw(ps) ∉ targets
        discarded_program_piece *= peek_raw(ps)
        discard!(ps)
    end
    text_pos_post = peek(ps).range.start - 1
    return (text_pos_pre, text_pos_post), discarded_program_piece
end

struct ParseException <: Exception end

function process_toplevel!(ps::ProcessState)
    expect_and_discard!(ps, "model")
    expect!(ps, "{", "begin")
    try # use exception to discard call stack
        process_statements!(ps)
    catch e
        if e isa ParseException
            try_recovery!(ps)
            return nothing
        else
            rethrow(e)
        end
    end
    if peek(ps) != K"}"
        add_diagnostic!(
            ps,
            "Parsing finished without get to the end of the program. $(peek_raw(ps)) is not expected to lead an statement.",
        )
    end
    expect!(ps, "}", "end")
    return process_trivia!(ps)
end

# panic mode recovery
function try_recovery!(ps)
    # seek to the closest sync point and dispatch to the corresponding `process_` function

    # sync points: for, ;, <, ~, {, } 
    # `\n` is not good, because we allow multiline expressions as C does
    (text_pos_pre, text_pos_post), discarded_program_piece = discard_until!(ps, ["for", ";", "<", "~", "{"])
    
    try
        if peek_raw(ps) == "for"
        elseif peek_raw(ps) == ";"
            consume!(ps)
            process_statements!(ps)
        elseif peek_raw(ps) in ("<", "~")
            recovery_function(ps) = process_assignment!(ps)
        elseif peek_raw(ps) == "{"
            # TODO: this is for loop body
        end
        # finish the current statement and move on
        # possibly throw exception while in a for loop
        process_statements!(ps) 
    catch e
        if e isa ParseException
            try_recovery!(ps)
        else
            rethrow(e)
        end
    end
end
```

Notes on the try on implementing `panic mode`:
* What I tried
    * throw an error when we detect that the `current_pos` is not moving forward. This is implemented implicitly in the `add_diagnostic!` function -- when two diagnostics are added with the same `current_pos`, then we throw an error
    * my plan was instead of throwing an error, we could enter panic mode and try to recover
    * conceptually, recovery is simple: We need to skip tokens until a synchronization point is found and then dispatch to the corresponding `process_` function
    * the issue is rooted in the mutual recursive nature of the program. When we throw an exception, we are in a deep call stack, so reentry to the previous function requires some thinking
    

    * **After some thinking** a monolithic recovery may not be the best idea; we should put try catch in
        * `process_for`: wrapping `process_statements!` so we have a chance to return to the for loop to wrap it up
        * `process_statements!`: wrap the while loop body
    * point is the recovery requirements are different for different functions, so we should put the try-catch in the functions themselves
