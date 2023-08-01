Strictly speaking, the program is not "parsing", because the program doesn't output a syntax tree. 
What is program does is take a token stream, with recursive descent structure, check the correctness of the program. 
In the process of the recursive descent, BUGS syntax tokens will be translated into Julia syntax tokens. 
The tokens that are already compatible with Julia will be remained, others will be either transformed or removed, also additional tokens may also be added.

The parser will error given a program not in strict BUGS syntax.

the general idea is:
1. use `tokenize` to get the token vector
2. inspect tokens and build the Julia version of the program in the form of a vector of tokens
3. when it is appropriate to do so, just push the token to the Julia version of the program vector
4. at the same time, some errors are detected and diagnostics are pushed to the diagnostics vector; also some tokens may be deleted, combined, or replaced 


## Some Notes on error recovery
The current error recovery is ad hoc and mostly primitive.
The parser is written in a way that if the program is correct, then the program will descent into the correct function, thus produce correct result. If the program is not correct, the wavefront of the token stream will not be pushed forward, thus it will fail. 
One of failure detection mechanism is to check if two error occurs with the same "current token". If there are, then the parser will stop and report the error. This is reassuring in the sense that the parser will not parse wrong programs. 
(Maybe instead of giving up, we can enter the recovery(panic) mode, find a rendezvous(synchronization) point, and continue parsing. This is not that straightforward because the sometimes we are in a deep call stack. The most straight forward way to implement using exception handling
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

Panic mode is a last resort. Ideally, we want try to sync up the parsing state and just continue parsing. Some thoughts:
* Singular error
    * Misspell
        * The misspelt word is parsed into a single token
            * The right thing to do is just record the diagnostic and discard and continue parsing
            * Reliable detection is difficult, especially misspelt word can be parsed into multiple tokens, so by simply checking the next token is not enough, but might be a good enough heuristic
        * The misspelt word is parsed into multiple tokens
            * The right thing in this case is to skip all the tokens birthed by the misspelt word, and continue parsing
            * This might not be that bad, because we whitelist the tokens that can be parsed into multiple tokens
    * Missing
        * the right thing to do is just simply continue without consuming or discarding
    * Extra
        * the right thing is to discard until the start of the next state
* Consecutive errors
    * This can be very tricky, because the detection is very difficult in the worst case. If we have a state syncing function for every state, and the lookahead length is 2, then we can match the "next token" and enter the next state and then try to sync again in that state.

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
    return seek_index # maybe actual location in the text 
end
```