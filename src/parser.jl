using CombinedParsers
using CombinedParsers: Delayed, word_char



@with_names begin
    ######### PRIMITIVES #############################################################
    
    newline_space = map(Returns(nothing), horizontal_space_maybe * vertical_space * horizontal_space_maybe)
    
    # <letter> ::= "a" .. "z"   |  "A".."Z " | "?".."?.." |  "?".."?"
    letter = ValueIn(:L) # "Letter" unicode class
    
    # <name> ::= <letter> [ { <letter> | <digit> | UNDERSCORE | PERIOD } ]
    name = map(Symbol, !(letter * Repeat(word_char | ".")))

    # <digit> ::= "0".."9"
    # <sign> ::= PLUS | MINUS
    # <integer> ::= <digit> [ {digit} ]
    integer = NumericParser(Int64)

    # <real> ::= [ <integer> ] PERIOD <integer> [ EXPONENT <sign> <integer> ] 
    real = NumericParser(Float64)
    
    # <number> ::= [ <sign > ] ( <integer> | < real> )
    number = Either{Real}(integer, real)

    index = Delayed(Union{Symbol, Expr, Real})

    # # <scalar> ::= <name> [ SQUAREL <index> { COMMA <index> } SQUARER ]
    scalar = Either{Union{Symbol, Expr}}(
        map(s -> :($(s.name)[$(s.indices...)]),
            Sequence(
                :name => name,
                :indices => Sequence(
                    "[",
                    space_maybe,
                    Either(
                        map(Returns(()), Sequence()),
                        map(i -> tuple(i), index),
                        map(t -> (t[begin], t[end]), index * space_maybe * "," * space_maybe * index),
                    ),
                    space_maybe,
                    "]",
                )[3]
            )
        ),
        name,
    )
    
    # <index> ::= <integer> | <scalar>
    # recursion
    push!(index, scalar)
    push!(index, integer)
    
    # <range> ::= ( <index> [ COLON  <index> ] ) | SPACE
    range = Either(
        index,
        map(t -> t[begin]:t[end], index * space_maybe  * ":" * space_maybe * index)
    )
    
    # <tensor> ::= <name> SQUAREL <range> [ { COMMA <range> } ] SQUARER
    tensor = map(Sequence(
        :name => name,
        "[",
        space_maybe,
        :ranges => Either(
            map(r -> tuple(r), range),
            map(t -> (t[begin], t[end]), range * space_maybe * "," * space_maybe * range)
        ),
        space_maybe,
        "]"
    )) do (name, ranges)
        return :($name[$(ranges...)])
    end


    # ############ EXPRESSIONS ####################################################################
    
    # <unary_function_name> ::= ABS | ARCCOS| ARCCOSH | ARCSIN | ARCSINH | ARCTAN |
        # ARCTANH | CLOGLOG | COS | COSH|  EXP | ICLOGLOG | ILOGIT | LOG |  LOGFACT |
        # LOGGAM | LOGIT | PHI | ROUND | SIN | SINH | SOFTPLUS | SQRT | STEP | TAN | TANH | TRUNC
    unary_function_name = Either(
        "abs", "arccos| arccosh", "arcsin", "arcsinh", "arctan", "arctanh", "cloglog", "cos",
        "cosh", "exp", "icloglog", "ilogit", "log", "logfact", "loggam", "logit", "phi", "round",
        "sin", "sinh", "softplus", "sqrt", "step", "tan", "tanh", "trunc"
    )
    # <binary_function_name> ::= EQUALS | MAX | MIN | POWER
    binary_function_name = Either("equals", "max", "min", "power")

    # <link_function> ::= CLOGLOG | LOG | LOGIT | PROBIT
    link_function_name = Either("cloglog", "log", "logit", "probit")

    # <argument> ::= <scalar> | <tensor> | <number>
    argument = scalar | tensor | number
    
    # <argument_list> ::= [ <argument> { COMMA <argument> } ]
    argument_list = join(argument, space_maybe * "," * space_maybe)

    # # <external_function> ::= <name> BRACKETL <argument_list> BRACKETR
    # external_function = Sequence(
    #     :name => name,
    #     "(",
    #     space_maybe,
    #     :arguments => argument_list,
    #     space_maybe,
    #     ")"
    # )

    # # <tensor_function> ::= <name> BRACKETL <argument_list> BRACKETR
    # tensor_function = Sequence(
    #     :name => name,
    #     "(",
    #     space_maybe,
    #     :arguments => argument_list,
    #     space_maybe,
    #     ")"
    # )

    # expression = Delayed(Any)
    
    # # <unary_internal_function> ::= <unary_function_name> BRACKETL <expression>  BRACKETR
    # # <binary_internal_function> ::= <binary_function_name> BRACKETL <expression> COMMA <expression>  BRACKETR
    # internal_function = Sequence(
    #     :name => (unary_function_name | binary_function_name),
    #     "(",
    #     space_maybe,
    #     :arguments => join(Repeat(1, 2, expression), space_maybe * "," * space_maybe),
    #     space_maybe,
    #     ")"
    # )

    # # <lhs> ::= <scalar> | <link_function> BRACKETL <scalar> BRACKETR
    # link_function = Sequence(
    #     :name => link_function_name,
    #     "(",
    #     space_maybe,
    #     :argument => scalar,
    #     space_maybe,
    #     ")"
    # )
    
    # # <factor> ::= [ MINUS ] (BRACKETL  <expression> BRACKETR |  <number> | <scalar> |
    # #     <unary_internal_function> | <binary_internal_function> | <external_function> )
    # factor = Sequence(
    #     :sign => Optional(CharIn("+-"), default="+"),
    #     space_maybe,
    #     Either(
    #         Sequence("(", space_maybe, expression, space_maybe, ")")[3],
    #         number,
    #         scalar,
    #         internal_function,
    #         external_function
    #     )
    # )
    
    # # <term> ::= <factor> | <term> ( MULT | DIV ) <factor>
    # term = Either(factor)
    # push!(term, Sequence(
    #     :lhs => term,
    #     space_maybe,
    #     CharIn("*/"),
    #     space_maybe,
    #     factor
    # ))

    
    # # <expression> ::= <term> | <expression> ( PLUS | MINUS ) <term>
    # # recursion
    # push!(expression, term)
    # push!(expression, Sequence(
    #     :lhs => expression,
    #     space_maybe,
    #     CharIn("+-"),
    #     :rhs => term
    # ))
    
    # # <distribution> ::= <name> BRACKETL <argument_list> BRACKETR
    # distribution = Sequence(
    #     :name => name,
    #     "(",
    #     space_maybe,
    #     :arguments => argument_list,
    #     space_maybe,
    #     ")"
    # )

    # # <censored> ::= CENSOR BRACKETL [ <scalar> ] COMMA [ <scalar> ] BRACKETR
    # censored = Sequence(
    #     "C",
    #     "(",
    #     space_maybe,
    #     :left => scalar,
    #     space_maybe,
    #     ",",
    #     space_maybe,
    #     :right => scalar,
    #     space_maybe,
    #     ")"
    # )
    
    # # <truncated> ::= TRUNCATE BRACKETL [ <scalar> ] COMMA  [ <scalar> ] BRACKETR
    # censored = Sequence(
    #     "T",
    #     "(",
    #     space_maybe,
    #     :left => scalar,
    #     space_maybe,
    #     ",",
    #     space_maybe,
    #     :right => scalar,
    #     space_maybe,
    #     ")"
    # )



    # ##### STATEMENTS ##################################################################

    # # <uni_statement>  ::= <scalar> DISTRIBUTED <distribution> [ <censored> ] [ <truncated> ]
    # uni_statement = Sequence(
    #     :lhs => scalar,
    #     space_maybe,
    #     "~",
    #     space_maybe,
    #     :rhs => distribution,
    #     :censored => Optional(censored),
    #     :truncated => Optional(truncated)
    # )

    # # <multi_statement> ::= <tensor> DISTRIBUTED <distribution>
    # multi_statement = Sequence(
    #     :lhs => tensor,
    #     space_maybe,
    #     "~",
    #     space_maybe,
    #     :rhs => distribution
    # )

    # # <stochastic_statement> ::= <uni_statement> | <multi_statement>
    # stochastic_statement = uni_statement | multi_statement

    # # <scalar_statement> ::= <lhs> BECOMES <expression>
    # scalar_statement = Sequence(
    #     :lhs => (scalar | link_function),
    #     space_maybe,
    #     "<-",
    #     space_maybe,
    #     :rhs => expression
    # )

    # # <tensor_statement> ::= <tensor> BECOMES <tensor_function>
    # tensor_statement = Sequence(
    #     :lhs => tensor,
    #     space_maybe,
    #     "<-",
    #     space_maybe,
    #     :rhs => tensor_function
    # )

    # # <logical_statement> ::= <scalar_statement> | <tensor_statement>
    # logical_statement = scalar_statement | tensor_statement
    
    # # <simple_statement> ::= <stochastic_statement> | <logical_statement>
    # simple_statement = stochastic_statement | logical_statement

    # statements = Delayed(Any)
   
    # # <for_statement> ::= FOR BRACKETL <name> IN <index> COLON <index> BRACKETR BRACEL { <statement> } BRACER
    # for_statement = Sequence(
    #     "for",
    #     "(",
    #     space_maybe,
    #     :varname => name,
    #     space,
    #     "in",
    #     space,
    #     :ix_start => index,
    #     space,
    #     ":",
    #     space,
    #     :ix_end => index,
    #     space_maybe,
    #     ")",
    #     space_maybe,
    #     "{",
    #     space_maybe,
    #     :body => statements,
    #     space_maybe,
    #     "}"
    # )

    # # <if_statement> ::= IF BRACKETL <scalar> BRACKETR BRACEL { <statement> } BRACER
    # if_statement = Sequence(
    #     "if",
    #     "(",
    #     space_maybe,
    #     :condition => scalar,
    #     space_maybe,
    #     ")",
    #     space_maybe,
    #     "{",
    #     space_maybe,
    #     :body => statements,
    #     space_maybe,
    #     "}"
    # )

    # # <compound_statement> ::= <for_statement> | <if_statement>
    # compound_statement = for_statement | if_statement
    
    # # <statement> ::= <compound_statement> | <simple_statement>
    # statement = compound_statement | simple_statement

    # # Recursion
    # push!(statements, join(Repeat(statement), newline_space))
    
    # # <program> ::= MODEL [ <name> ] BRACEL { <statement> } BRACER
    # program = Sequence(
    #     space_maybe,
    #     "model",
    #     space,
    #     :name => Optional(name),
    #     space,
    #     "{",
    #     space_maybe,
    #     :body => statements,
    #     space_maybe,
    #     "}",
    #     space_maybe
    # )
end

# @syntax bugs = program
