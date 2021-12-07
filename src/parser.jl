using CombinedParsers
using CombinedParsers: Delayed, word_char


const Value = Union{Symbol, Real, Expr}


@with_names begin
    const newline_space = map(
        Returns(nothing),
        horizontal_space_maybe * vertical_space * horizontal_space_maybe
    )
end

function intersperse(as, b)
    return Iterators.take(
        Iterators.flatten(Iterators.zip(as, Iterators.repeated(b))),
        2length(as) - 1
    )
end

separated(parsers...; separator = space_maybe) = Sequence(intersperse(parsers, separator)...)
separated(transform::Union{Int, Function}, parsers...; separator = space_maybe) =
    Sequence(transform, intersperse(parsers, separator)...)


######### PRIMITIVES #############################################################
@with_names begin
    # <letter> ::= "a" .. "z"   |  "A".."Z " | "?".."?.." |  "?".."?"
    const letter = ValueIn(:L) # "Letter" unicode class
    
    # <name> ::= <letter> [ { <letter> | <digit> | UNDERSCORE | PERIOD } ]
    const name = map(Symbol, !(letter * Repeat(word_char | ".")))

    # <digit> ::= "0".."9"
    # <sign> ::= PLUS | MINUS
    # <integer> ::= <digit> [ {digit} ]
    const integer = NumericParser(Int64)

    # <real> ::= [ <integer> ] PERIOD <integer> [ EXPONENT <sign> <integer> ] 
    const real = NumericParser(Float64)
    
    # <number> ::= [ <sign > ] ( <integer> | < real> )
    const number = Either{Real}(integer, real)

    const index = Delayed(Value)

    # <scalar> ::= <name> [ SQUAREL <index> { COMMA <index> } SQUARER ]
    const scalar = Either{Value}(
        Sequence(
            # s -> Expr(:scalar, :($(s.name)[$(s.indices...)])),
            s -> :($(s.name)[$(s.indices...)]),
            :name => name,
            :indices => Either(
                separated("[", :i1 => index, ",", :i2 => index, "]"),
                separated("[", :i => index, "]"),
                map(Returns((;)), "[", "]")
            )
        ),
        # map(n -> Expr(:scalar, n), name)
        name
    )

    push!(index, integer)
    push!(index, scalar)
    
    # <range> ::= ( <index> [ COLON  <index> ] ) | SPACE
    # NOTE: should not be an integer...
    const range = separated(:i1 => index, ":", :i2 => index) do s
        :($(s.i1):$(s.i2))
    end
    
    # <tensor> ::= <name> SQUAREL <range> [ { COMMA <range> } ] SQUARER
    const tensor = Sequence(
        :name => name,
        :ranges => Either(
            separated("[", :r1 => range, ",", :r2 => range, "]"),
            separated("[", :r => range, "]"),
        )
    ) do (name, ranges)
        # return Expr(:tensor, :($name[$(ranges...)]))
        return :($name[$(ranges...)])
    end
end

############ EXPRESSIONS ####################################################################
@with_names begin
    # <argument> ::= <scalar> | <tensor> | <number>
    # <argument_list> ::= [ <argument> { COMMA <argument> } ]
    # <external_function> ::= <name> BRACKETL <argument_list> BRACKETR
    # <tensor_function> ::= <name> BRACKETL <argument_list> BRACKETR
    # This gets simlified: we just parse functions as expressions, and type-check at a later phase.
    
    expression = Delayed(Value)
    
    argument_list = Optional(join(Repeat(expression), space_maybe * "," * space_maybe))
    
    funcall = Sequence(
        :name => name,
        "(",
        space_maybe,
        :arguments => argument_list,
        space_maybe,
        ")"
    ) do (name, arguments)
        return :($name($(arguments...)))
    end
    
    # <lhs> ::= <scalar> | <link_function> BRACKETL <scalar> BRACKETR
    link_function = map(funcall -> Expr(:link, funcall), funcall)

    # <factor> ::= [ MINUS ] (BRACKETL  <expression> BRACKETR |  <number> | <scalar> |
    #     <unary_internal_function> | <binary_internal_function> | <external_function> )
    factor = separated(
        :sign => Optional(CharIn("+-")),
        :expression => Either{Value}(
            Sequence(3, "(", space_maybe, expression, space_maybe, ")"),
            funcall,
            number,
            tensor,
            scalar,
        )
    ) do (sign, expression)
        if sign === missing
            return expression
        else
            return Expr(:call, Symbol(sign), expression)
        end
    end

    # <term> ::= <factor> | <term> ( MULT | DIV ) <factor>
    # AFTER LEFT RECURSION ELIMINATION:
    # <term> ::= <factor> { ( MULT | DIV ) <factor> }
    term = join(Repeat(factor), trim(CharIn("*/"), whitespace=space_maybe), infix=:prefix) do (x, xs)
        return foldl((w, (op, v)) -> Expr(:call, Symbol(op), w, v), xs, init=x)::Value
    end

    # <expression> ::= <term> | <expression> ( PLUS | MINUS ) <term>
    # AFTER LEFT RECURSION ELIMINATION:
    # <expression> ::= <term> { (PLUS | MINUS) <term>}
    push!(
        expression,
        join(Repeat(term), trim(CharIn("+-"), whitespace=space_maybe), infix=:prefix) do (x, xs)
            return foldl((w, (op, v)) -> Expr(:call, Symbol(op), w, v), xs, init=x)::Value
        end
    )

    
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
