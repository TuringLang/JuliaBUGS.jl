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
5. error recovery is very primitive: the heuristic is user forget something instead of put something wrong, a slightly more sophisticated approach is doing two versions: both "discard" and skip
