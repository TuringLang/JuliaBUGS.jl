using JuliaBUGS: to_julia_program
using JuliaSyntax
using JuliaSyntax: @K_str, ParseError

function parse_bugs(prog, replace_period=true, no_enclosure=false)
    julia_program = to_julia_program(prog, replace_period, no_enclosure)
    expr = Base.Expr(JuliaSyntax.parsestmt(SyntaxNode, julia_program))
    expr = MacroTools.postwalk(MacroTools.rmlines, expr)
    return expr
end

@testset "BUGS Parser for String macro" begin
    @testset "Unit tests for process_*" begin
        using JuliaBUGS.Parser:
            ProcessState,
            process_toplevel!,
            process_trivia!,
            peek,
            peek_raw,
            process_variable!,
            process_expression!,
            process_assignment!,
            process_for!,
            process_range!,
            process_indexing!,
            process_tilde_rhs!

        @testset "process_toplevel!" begin
            # Test 1: Enclosure
            ps = ProcessState("model { }")
            process_toplevel!(ps)
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)
        end

        @testset "process_indexing!" begin
            # Test 1
            ps = ProcessState("[1, 2, 3]")
            process_indexing!(ps)
            @test to_julia_program(ps) == "[1, 2, 3]"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)
        end

        @testset "process_variable!" begin
            # Test 1: Trivial variable trailing with whitespace
            ps = ProcessState("a ")
            process_variable!(ps)
            @test to_julia_program(ps) == "a"
            @test peek(ps) == K"Whitespace"
            @test isempty(ps.diagnostics)

            # Test 2: R-style variable
            ps = ProcessState("a.b.c")
            process_variable!(ps)
            @test to_julia_program(ps) == "a_b_c"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)

            # Test 3: Variable with indexing
            ps = ProcessState("a.b.c[1, 2, 3]", false, true)
            process_variable!(ps)
            @test to_julia_program(ps) == "var\"a.b.c\"[1, 2, 3]"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)
        end

        @testset "process_expression!" begin
            # Test 1
            ps = ProcessState("a + b")
            process_expression!(ps)
            @test to_julia_program(ps) == "a + b"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)
        end

        @testset "process_indexing!" begin
            # Test 1: implicit indexing
            ps = ProcessState("[, 3]")
            process_indexing!(ps)
            @test to_julia_program(ps) == "[:, 3]"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)
        end

        @testset "process_tilde_rhs!(ps)" begin
            # Test 1: Truncated and Censoring expression
            ps = ProcessState("dflat()T(-1000, a[2])")
            process_tilde_rhs!(ps)
            @test to_julia_program(ps) == " truncated(dflat(), -1000, a[2])"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)
        end

        @testset "process_assignment!" begin
            # Test 1: Trivial assignment
            ps = ProcessState("a <- 1")
            process_assignment!(ps)
            @test to_julia_program(ps) == "a = 1"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)

            # Test 2: Assignment with indexing
            ps = ProcessState("a.b.c[1, 2, 3] <- 1")
            process_assignment!(ps)
            @test to_julia_program(ps) == "a_b_c[1, 2, 3] = 1"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)

            # Test 3
            ps = ProcessState("x = 1+12")
            process_assignment!(ps)
            @test to_julia_program(ps) == "x = 1+12"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)

            # Test 4: Tilde assignment
            ps = ProcessState("alpha[i] ~ dnorm(alpha.c, alpha.tau)")
            process_assignment!(ps)
            @test to_julia_program(ps) == "alpha[i] ~ dnorm(alpha_c, alpha_tau)"
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)
        end

        @testset "process_for!" begin
            # Test 1
            ps = ProcessState("for (i in 1:10) { a[i] <- 1 }")
            process_for!(ps)
            @test to_julia_program(ps) == "for   i in 1:10    a[i] = 1  end" # extra whitespace is inserted
            @test peek(ps) == K"EndMarker"
            @test isempty(ps.diagnostics)
        end

        @testset "test_process_trivia!" begin
            # Test 1: Processing whitespace
            ps = ProcessState("   model")
            process_trivia!(ps)
            @test ps.current_index == 2
            @test peek_raw(ps) == "model"

            # Test 2: Processing comments
            ps = ProcessState("# This is a comment\nmodel")
            process_trivia!(ps)
            @test ps.current_index == 3
            @test peek_raw(ps) == "model"

            # Test 3: Not processing newline when skip_newline is false
            ps = ProcessState("\nmodel")
            process_trivia!(ps, false)
            @test ps.current_index == 1
            @test peek_raw(ps) == "\n"

            # Test 4: Processing newline when skip_newline is true
            ps = ProcessState("\nmodel")
            process_trivia!(ps, true)
            @test ps.current_index == 2
            @test peek_raw(ps) == "model"
        end
    end

    @testset "Tokenizer corner cases" begin
        # tokenize errors are generally corner cases that are side effects of the tokenizer
        # and the fact that it's designed for Julia, not BUGS
        # one such corner case: `<---2` will not be tokenized to `<--` and `-2`, but `InvalidOperator` and `-2` 

        # BUGS doesn't have a `<--` operator, but this is left as a reminder
        @test_throws ParseError JuliaBUGS.Parser.ProcessState("<---2")
    end

    @testset "Basic statements" begin
        parse_bugs(
            """
     alpha ~ dnorm(0, 1e-6)
     alpha[x[1:2]] ~ dflat() # nested indexing
     log(sigma2) <- 2*log.sigma # link function
     log.sigma ~ dflat() # variable starts with one of the link function names

     for (i in 1:20) { Y[i, 1:4] ~ dmnorm(mu[], Sigma.inv[,]) } # implicit indexing
     for (j in 1:4) {
         mu[j] <- alpha + beta*x[j]
         sigma ~ dgamma(0.001, 0.001) # multi-line for loop
     }
    """,
            true,
            true,
        )
    end

    @testset "Corner case: `<-1` tokenized as `<` and `-1`" begin
        @test parse_bugs("model{a <- 1}") == MacroTools.@q begin
            a = 1
        end
    end

    @testset "RHS lead by a minus sign" begin
        to_julia_program("y <- -x + 1+ f(x)", true, true)
    end

    @testset "Corner cases with brackets" begin
        parse_bugs("model{}")

        ref_rst = MacroTools.@q begin
            for i in 1:10
                a[i] = 1
            end
        end
        @test parse_bugs("model{
            for (i in 1:10) {a[i] <- 1}
        }") == ref_rst
        @test parse_bugs("model{
            for (i in 1:10) {a[i] <- 1}
        }") == ref_rst
        @test parse_bugs("model{
            for(i in 1:10){ a[i] <- 1}
        }") == ref_rst
        @test parse_bugs("model{
            for(i in 1:10){a[i] <- 1}
        }") == ref_rst
    end

    @testset "Truncation and Censoring" begin
        @test parse_bugs(
            """
           a ~ dwish(R[,], 4) C (0, 1)
           a ~ dwish(R[,], 4) C (,1)
           a ~ dwish(R[,], 4) C (0,)
           a ~ dwish(R[,], 4) T (0, 1)
        """,
            true,
            true,
        ) == MacroTools.@q begin
            a ~ censored(dwish(R[:, :], 4), 0, 1)
            a ~ censored(dwish(R[:, :], 4), nothing, 1)
            a ~ censored(dwish(R[:, :], 4), 0, nothing)
            a ~ truncated(dwish(R[:, :], 4), 0, 1)
        end
    end

    @testset "One statement across multiple lines" begin
        @test parse_bugs(
            """
        model {
           solution[1:ngrid, 1:ndim] <- ode.solution(init[1:ndim], tgrid[1:ngrid], D(C[1:ndim], t),
           origin, tol)
        }
        """,
        ) == MacroTools.@q begin
            solution[1:ngrid, 1:ndim] = ode_solution(
                init[1:ndim], tgrid[1:ngrid], D(C[1:ndim], t), origin, tol
            )
        end
    end

    @testset "Fail cases" begin
        # unknown link functions
        @test_throws ParseError to_julia_program("f(p[1]) <- logit.p[1]", true, true)

        # link function on the LHS of a stochastic assignment
        @test_throws ErrorException JuliaBUGS.Parser._bugs_string_input(
            "logit(p[1]) ~ dnorm(0, 1)", true, true
        )

        # expression as lhs
        @test_throws ParseError to_julia_program("logit(p + 1) <- logit.p + 1", true, true)
        @test_throws ParseError to_julia_program("p + 1 <- logit.p + 1", true, true)
        @test_throws ParseError to_julia_program(
            "logit(p[1], 1) <- logit.p[1] + 1", true, true
        )

        # white space between function name and parenthesis
        @test_throws ParseError to_julia_program("b.apd ~ dnorm (0, 1.0E-03)", true, true)
        @test_throws ParseError to_julia_program("y = f (x, z)", true, true)
    end
end
