using Lerche

# bugs_grammar = raw"""
# ?start: expression

# ?expression: value

# // PRIMITIVES
# ?value: number
#       | indexed_variable 
#       | variable

# indexed_variable: NAME "[" _sepby{expression?, ","} "]"
# variable: NAME
# range: expression ":" expression
# number: SIGNED_FLOAT -> real
#       | SIGNED_INT -> integer

# // LITERALS
# LETTER: /\p{L}/
# WORD_CHAR: LETTER | DIGIT | "_" | "."
# NAME: LETTER WORD_CHAR*

# // UTILS
# _function_call{name, args}: name "(" args ")"
# _sepby{p, sep}: [p (sep p)*]
# _sepby1{p, sep}: p (sep p)*

# COMMENT: "#" /[^\n]/*
# %ignore COMMENT

# WS: /(?>[[:space:]]+)/
# %ignore WS

# %import common.DIGIT
# %import common.SIGNED_INT
# %import common.SIGNED_FLOAT
# """

bugs_grammar() = raw"""
start: s
s: [name ("," name)*]
name: ["x"]

WS: /(?>[[:space:]]+)/
%ignore WS
"""

struct BugsTransformer <: Transformer end

parse(text) = Lerche.parse(
    Lark(
        bugs_grammar(),
        parser="lalr",
        lexer="standard",
        # maybe_placeholders=true,
        transformer=BugsTransformer(),
    ),
    text
)
    
