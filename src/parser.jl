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

trimmed(p) = trim(p, whitespace = space_maybe)

function function_parser(p_name, p_argument_list)
    return Sequence(
        :name => p_name,
        "(",
        space_maybe,
        :arguments => p_argument_list,
        space_maybe,
        ")"
    )
end


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

    # <index> ::= <integer> | <scalar>
    const index = Delayed(Value)
    
    # <range> ::= ( <index> [ COLON  <index> ] ) | SPACE
    const range = Either(
        separated(:i1 => index, ":", :i2 => index) do (i1, i2)
            :($i1:$i2)
        end,
        index,
        map(Returns(:(:)), space_maybe)
    )
    
    # <scalar> ::= <name> [ SQUAREL <index> { COMMA <index> } SQUARER ]
    # <tensor> ::= <name> SQUAREL <range> [ { COMMA <range> } ] SQUARER
    const variable = name
    const indexed_variable = Sequence(
        :name => name,
        "[",
        space_maybe,
        :indices => join(Repeat(range), trimmed(",")),
        space_maybe,
        "]"
    ) do (name, indices)
        return :($(name)[$(indices...)])
    end

    push!(index, integer)
    push!(index, indexed_variable)
    push!(index, variable)
    
    const value = number | indexed_variable | variable
end

############ EXPRESSIONS ####################################################################
@with_names begin
    # <argument> ::= <scalar> | <tensor> | <number>
    # <argument_list> ::= [ <argument> { COMMA <argument> } ]
    # <external_function> ::= <name> BRACKETL <argument_list> BRACKETR
    # <tensor_function> ::= <name> BRACKETL <argument_list> BRACKETR
    # This gets simlified: we just parse functions as expressions, and type-check at a later phase.
    
    const expression = Delayed(Value)
    
    const funcall = map(
        function_parser(name, Optional(join(Repeat(expression), trimmed(","))))
    ) do (name, arguments)
        return :($name($(arguments...)))
    end

    # <factor> ::= [ MINUS ] (BRACKETL  <expression> BRACKETR |  <number> | <scalar> |
    #     <unary_internal_function> | <binary_internal_function> | <external_function> )
    const factor = separated(
        :sign => Optional(CharIn("+-")),
        :expression => Either{Value}(
            Sequence(3, "(", space_maybe, expression, space_maybe, ")"),
            funcall,
            value,
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
    const term = join(Repeat(factor), trimmed(CharIn("*/")), infix=:prefix) do (x, xs)
        return foldl((w, (op, v)) -> Expr(:call, Symbol(op), w, v), xs, init=x)::Value
    end

    # <expression> ::= <term> | <expression> ( PLUS | MINUS ) <term>
    # AFTER LEFT RECURSION ELIMINATION:
    # <expression> ::= <term> { (PLUS | MINUS) <term>}
    push!(
        expression,
        join(Repeat(term), trimmed(CharIn("+-")), infix=:prefix) do (x, xs)
            return foldl((w, (op, v)) -> Expr(:call, Symbol(op), w, v), xs, init=x)::Value
        end
    )
    
    # <distribution> ::= <name> BRACKETL <argument_list> BRACKETR
    const distribution = map(
        function_parser(name, Optional(join(Repeat(expression), trimmed(","))))
    ) do (name, arguments)
        return :($name($(arguments...)))
    end

    # TODO: sure that this should be <scalar>, not (<number> | <scalar>)?
    # <censored> ::= CENSOR BRACKETL [ <scalar> ] COMMA [ <scalar> ] BRACKETR
    # TODO: what about empty bounds, `C(1,)`
    const censored = map(
        function_parser(
            map(Symbol, parser("C")), separated(:l => value, ",", :r => value)
        )
    ) do (_, censoring)
        return censoring
    end

    # TODO: sure that this should be <scalar>, not (<number> | <scalar>)?
    # TODO: what about empty bounds, `T(1,)`
    # <truncated> ::= TRUNCATE BRACKETL [ <scalar> ] COMMA  [ <scalar> ] BRACKETR
    const truncated = map(
        function_parser(
            map(Symbol, parser("T")), separated(:l => value, ",", :r => value)
        )
    ) do (_, truncation)
        return truncation
    end
end


##### STATEMENTS ##################################################################
@with_names begin
    # <uni_statement> ::= <scalar> DISTRIBUTED <distribution> [ <censored> ] [ <truncated> ]
    # <multi_statement> ::= <tensor> DISTRIBUTED <distribution>
    # <stochastic_statement> ::= <uni_statement> | <multi_statement>
    # TODO: constants on LHS?
    const stochastic_statement = separated(
        :lhs => (indexed_variable | variable),
        "~",
        :rhs => distribution,
        :censoring => Optional(censored),
        :truncation => Optional(truncated)
    ) do (lhs, rhs, censoring, truncation)
        if !ismissing(censoring)
            rhs = Expr(:censored, rhs, censoring...)
        end

        if !ismissing(truncation)
            rhs = Expr(:truncation, rhs, truncation...)
        end
        
        return Expr(:call, :~, lhs, rhs)
    end
    
    # link_function = map(funcall -> Expr(:link, funcall), funcall)
    const link_function = function_parser(name, Sequence(indexed_variable | variable))

    # <lhs> ::= <scalar> | <link_function> BRACKETL <scalar> BRACKETR
    const lhs = indexed_variable | variable | link_function
    
    # <scalar_statement> ::= <lhs> BECOMES <expression>
    # <tensor_statement> ::= <tensor> BECOMES <tensor_function>
    # <logical_statement> ::= <scalar_statement> | <tensor_statement>
    const logical_statement = separated(
        :lhs => lhs,
        "<-",
        :rhs => expression
    ) do (lhs, rhs)
        return Expr(:(=), lhs, rhs)
    end

    # <simple_statement> ::= <stochastic_statement> | <logical_statement>
    const simple_statement = stochastic_statement | logical_statement

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
