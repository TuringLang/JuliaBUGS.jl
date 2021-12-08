using CombinedParsers
using CombinedParsers: Delayed, word_char


const Value = Union{Symbol, Real, Expr}

function bugs(x)
    @with_names begin
        newline_space = map(
            Returns(nothing),
            Sequence(
                horizontal_space_maybe,
                vertical_space,
                space_maybe
            )
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

        # <index> ::= <integer> | <scalar>
        index = Delayed(Value)
        
        # <range> ::= ( <index> [ COLON  <index> ] ) | SPACE
        range_literal = separated(:i1 => index, ":", :i2 => index) do (i1, i2)
            :($i1:$i2)
        end
        range = Either(
            range_literal,
            index,
            map(Returns(:(:)), space_maybe)
        )
        
        # <scalar> ::= <name> [ SQUAREL <index> { COMMA <index> } SQUARER ]
        # <tensor> ::= <name> SQUAREL <range> [ { COMMA <range> } ] SQUARER
        variable = name
        indexed_variable = Sequence(
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
        
        value = number | indexed_variable | variable
    end

    ############ EXPRESSIONS ####################################################################
    @with_names begin
        # <argument> ::= <scalar> | <tensor> | <number>
        # <argument_list> ::= [ <argument> { COMMA <argument> } ]
        # <external_function> ::= <name> BRACKETL <argument_list> BRACKETR
        # <tensor_function> ::= <name> BRACKETL <argument_list> BRACKETR
        # This gets simlified: we just parse functions as expressions, and type-check at a later phase.
        
        expression = Delayed(Value)
        
        funcall = map(
            function_parser(name, Optional(join(Repeat(expression), trimmed(","))))
        ) do (name, arguments)
            return :($name($(arguments...)))
        end

        # <factor> ::= [ MINUS ] (BRACKETL  <expression> BRACKETR |  <number> | <scalar> |
        #     <unary_internal_function> | <binary_internal_function> | <external_function> )
        factor = separated(
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
        term = join(Repeat(factor), trimmed(CharIn("*/")), infix=:prefix) do (x, xs)
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
        distribution = map(
            function_parser(name, Optional(join(Repeat(expression), trimmed(","))))
        ) do (name, arguments)
            return :($name($(arguments...)))
        end

        # TODO: sure that this should be <scalar>, not (<number> | <scalar>)?
        # <censored> ::= CENSOR BRACKETL [ <scalar> ] COMMA [ <scalar> ] BRACKETR
        # TODO: what about empty bounds, `C(1,)`
        censored = map(
            function_parser(
                map(Symbol, parser("C")), separated(:l => value, ",", :r => value)
            )
        ) do (_, censoring)
            return censoring
        end

        # TODO: sure that this should be <scalar>, not (<number> | <scalar>)?
        # TODO: what about empty bounds, `T(1,)`
        # <truncated> ::= TRUNCATE BRACKETL [ <scalar> ] COMMA  [ <scalar> ] BRACKETR
        truncated = map(
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
        stochastic_statement = separated(
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
        link_function = function_parser(name, Sequence(indexed_variable | variable))

        # <lhs> ::= <scalar> | <link_function> BRACKETL <scalar> BRACKETR
        lhs = indexed_variable | variable | link_function
        
        # <scalar_statement> ::= <lhs> BECOMES <expression>
        # <tensor_statement> ::= <tensor> BECOMES <tensor_function>
        # <logical_statement> ::= <scalar_statement> | <tensor_statement>
        logical_statement = separated(
            :lhs => lhs,
            "<-",
            :rhs => expression
        ) do (lhs, rhs)
            return Expr(:(=), lhs, rhs)
        end

        # <simple_statement> ::= <stochastic_statement> | <logical_statement>
        simple_statement = stochastic_statement | logical_statement

        statements = Delayed(Any)
        
        # <for_statement> ::= FOR BRACKETL <name> IN <index> COLON <index> BRACKETR BRACEL { <statement> } BRACER
        for_statement = separated(
            "for",
            "(",
            :varname => name,
            "in",
            :range => range_literal,
            ")",
            "{",
            :body => statements,
            "}"
        ) do (varname, range, body)
            return Expr(:for, Expr(:(=), varname, range), Expr(:block, body...))
        end

        # <if_statement> ::= IF BRACKETL <scalar> BRACKETR BRACEL { <statement> } BRACER
        if_statement = separated(
            "if",
            "(",
            :condition => value,
            ")",
            "{",
            :body => statements,
            "}"
        ) do (varname, range, body)
            return Expr(:if, condition, Expr(:block, body...))
        end

        # <compound_statement> ::= <for_statement> | <if_statement>
        compound_statement = for_statement | if_statement
        
        # <statement> ::= <compound_statement> | <simple_statement>
        statement = compound_statement | simple_statement

        # TODO: are newlines significant? where? allowed in expressions?
        push!(statements, Optional(join(Repeat(statement), newline_space)))
        
        # <program> ::= MODEL [ <name> ] BRACEL { <statement> } BRACER
        program = separated(
            space_maybe,
            "model",
            :name => Optional(name),
            "{",
            :body => statements,
            "}",
            space_maybe
        ) do (name, body)
            return Expr(:model, name, Expr(:block, body...))
        end
        
        bugs = program
    end

    return bugs(x)
end

macro bugsast_str(x)
    return bugs(x)
end

