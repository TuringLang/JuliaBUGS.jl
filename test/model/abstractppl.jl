# Tests for abstractppl.jl functions, specifically condition and decondition

using Test
using JuliaBUGS
using JuliaBUGS.Model: parse_conditioning_spec, check_conditioning_validity, mark_as_observed, update_evaluation_env, subgraph, parse_deconditioning_spec, check_deconditioning_validity, mark_as_unobserved, reset_evaluation_env
using AbstractPPL
using Random
using Distributions

@testset "condition and decondition implementation tests" begin
    
    # Create a simple test model
    function create_test_model()
        model_def = @bugs begin
            mu ~ Normal(0, 10)
            sigma ~ Uniform(0, 10)
            for i in 1:3
                x[i] ~ Normal(mu, sigma)
            end
        end
        data = (; y = 5.0)
        return compile(model_def, data)
    end
    
    @testset "condition function tests" begin
        
        @testset "Dict input" begin
            model = create_test_model()
            original_params = copy(model.parameters)
            
            # Condition on mu
            cond_model = condition(model, Dict(:mu => 1.5))
            
            @test cond_model.evaluation_env.mu == 1.5
            @test cond_model.g[@varname(mu)].is_observed
            @test @varname(mu) ∉ cond_model.parameters
            @test @varname(sigma) ∈ cond_model.parameters
            
            # Multiple variables
            cond_model2 = condition(model, Dict(:mu => 2.0, :sigma => 1.0))
            @test cond_model2.evaluation_env.mu == 2.0
            @test cond_model2.evaluation_env.sigma == 1.0
            @test @varname(mu) ∉ cond_model2.parameters
            @test @varname(sigma) ∉ cond_model2.parameters
        end
        
        @testset "Vector input" begin
            model = create_test_model()
            model = initialize!(model, (; mu=2.5, sigma=1.0))
            
            cond_model = condition(model, [:mu, :sigma])
            
            @test cond_model.evaluation_env.mu == 2.5
            @test cond_model.evaluation_env.sigma == 1.0
            @test cond_model.g[@varname(mu)].is_observed
            @test cond_model.g[@varname(sigma)].is_observed
            @test @varname(mu) ∉ cond_model.parameters
            @test @varname(sigma) ∉ cond_model.parameters
        end
        
        @testset "Pairs input" begin
            model = create_test_model()
            
            cond_model = condition(model, :mu => 1.5, :sigma => 2.0)
            
            @test cond_model.evaluation_env.mu == 1.5
            @test cond_model.evaluation_env.sigma == 2.0
            @test cond_model.g[@varname(mu)].is_observed
            @test cond_model.g[@varname(sigma)].is_observed
            @test @varname(mu) ∉ cond_model.parameters
            @test @varname(sigma) ∉ cond_model.parameters
        end
        
        @testset "NamedTuple input" begin
            model = create_test_model()
            
            cond_model = condition(model, (; mu=1.5, sigma=2.0))
            
            @test cond_model.evaluation_env.mu == 1.5
            @test cond_model.evaluation_env.sigma == 2.0
            @test cond_model.g[@varname(mu)].is_observed
            @test cond_model.g[@varname(sigma)].is_observed
            @test @varname(mu) ∉ cond_model.parameters
            @test @varname(sigma) ∉ cond_model.parameters
        end
        
        @testset "create_subgraph option" begin
            model = create_test_model()
            
            # With subgraph (default)
            cond_with_subgraph = condition(model, Dict(:mu => 1.5))
            
            # Without subgraph
            cond_without_subgraph = condition(model, Dict(:mu => 1.5), create_subgraph=false)
            
            # Both should have same conditioning
            @test cond_with_subgraph.evaluation_env.mu == cond_without_subgraph.evaluation_env.mu
            @test cond_with_subgraph.g[@varname(mu)].is_observed == cond_without_subgraph.g[@varname(mu)].is_observed
            
            # But different graph sizes
            @test length(cond_with_subgraph.flattened_graph_node_data.sorted_nodes) <= 
                  length(cond_without_subgraph.flattened_graph_node_data.sorted_nodes)
        end
        
        @testset "error handling" begin
            model = create_test_model()
            
            # Non-existent variable
            @test_throws ArgumentError condition(model, Dict(:nonexistent => 1.0))
            
            # Deterministic variable
            model_def = @bugs begin
                a ~ Normal(0, 1)
                b = a + 1
            end
            model = compile(model_def, NamedTuple())
            @test_throws ArgumentError condition(model, Dict(:b => 1.0))
        end
    end
    
    @testset "decondition function tests" begin
        
        @testset "basic decondition" begin
            model = create_test_model()
            
            # First condition on mu and sigma
            cond_model = condition(model, Dict(:mu => 1.0, :sigma => 0.5))
            @test @varname(mu) ∉ cond_model.parameters
            @test @varname(sigma) ∉ cond_model.parameters
            
            # Then decondition mu
            decond_model = decondition(cond_model, :mu)
            @test @varname(mu) ∈ decond_model.parameters
            @test @varname(sigma) ∉ decond_model.parameters  # still conditioned
            @test !decond_model.g[@varname(mu)].is_observed
            @test decond_model.g[@varname(sigma)].is_observed
        end
        
        @testset "decondition multiple variables" begin
            model = create_test_model()
            
            # Condition on mu and sigma
            cond_model = condition(model, Dict(:mu => 1.0, :sigma => 0.5))
            
            # Decondition both
            decond_model = decondition(cond_model, [:mu, :sigma])
            @test @varname(mu) ∈ decond_model.parameters
            @test @varname(sigma) ∈ decond_model.parameters
            @test !decond_model.g[@varname(mu)].is_observed
            @test !decond_model.g[@varname(sigma)].is_observed
        end
        
        @testset "decondition error handling" begin
            model = create_test_model()
            
            # Try to decondition unobserved variable
            @test_throws ArgumentError decondition(model, :mu)
            
            # Try to decondition non-existent variable
            cond_model = condition(model, Dict(:mu => 1.0))
            @test_throws ArgumentError decondition(cond_model, :nonexistent)
        end
    end
    
    @testset "helper function tests" begin
        
        @testset "parse_conditioning_spec tests" begin
            model = create_test_model()
            
            @testset "Dict input" begin
                # Test with Symbol keys
                spec = Dict(:mu => 1.0, :sigma => 2.0)
                result = parse_conditioning_spec(spec, model)
                @test result[@varname(mu)] == 1.0
                @test result[@varname(sigma)] == 2.0
                
                # Test with VarName keys
                spec = Dict(@varname(mu) => 1.0, @varname(sigma) => 2.0)
                result = parse_conditioning_spec(spec, model)
                @test result[@varname(mu)] == 1.0
                @test result[@varname(sigma)] == 2.0
            end
            
            @testset "Vector input" begin
                # Initialize model with some values
                model = initialize!(model, (; mu=3.0, sigma=1.5))
                
                spec = [:mu, :sigma]
                result = parse_conditioning_spec(spec, model)
                @test result[@varname(mu)] == 3.0
                @test result[@varname(sigma)] == 1.5
                
                # Test with VarName vector
                spec = [@varname(mu), @varname(sigma)]
                result = parse_conditioning_spec(spec, model)
                @test result[@varname(mu)] == 3.0
                @test result[@varname(sigma)] == 1.5
            end
            
            @testset "NamedTuple input" begin
                spec = (; mu=2.5, sigma=1.2)
                result = parse_conditioning_spec(spec, model)
                @test result[@varname(mu)] == 2.5
                @test result[@varname(sigma)] == 1.2
            end
        end
        
        @testset "check_conditioning_validity tests" begin
            model = create_test_model()
            
            @testset "valid variables" begin
                vars = [@varname(mu), @varname(sigma)]
                @test_nowarn check_conditioning_validity(model, vars)
            end
            
            @testset "non-existent variable" begin
                vars = [@varname(nonexistent)]
                @test_throws ArgumentError check_conditioning_validity(model, vars)
            end
            
            @testset "deterministic variable" begin
                # Create a model with a deterministic variable
                model_def = @bugs begin
                    a ~ Normal(0, 1)
                    b = a + 1  # deterministic
                    c ~ Normal(b, 1)
                end
                model = compile(model_def, NamedTuple())
                vars = [@varname(b)]
                @test_throws ArgumentError check_conditioning_validity(model, vars)
            end
            
            @testset "already observed variable" begin
                model = create_test_model()
                # First condition on mu to make it observed
                cond_model = condition(model, Dict(:mu => 1.0))
                vars = [@varname(mu)]
                # This should issue a warning but not throw
                @test_logs (:warn, r"already observed") check_conditioning_validity(cond_model, vars)
            end
        end
        
        @testset "mark_as_observed tests" begin
            model = create_test_model()
            vars = [@varname(mu), @varname(sigma)]
            new_graph = mark_as_observed(model.g, vars)
            
            @test new_graph[@varname(mu)].is_observed
            @test new_graph[@varname(sigma)].is_observed
            # Original graph should be unchanged
            @test !model.g[@varname(mu)].is_observed
            @test !model.g[@varname(sigma)].is_observed
        end
        
        @testset "update_evaluation_env tests" begin
            model = create_test_model()
            var_values = Dict(@varname(mu) => 2.0, @varname(sigma) => 3.0)
            
            new_env = update_evaluation_env(model.evaluation_env, var_values)
            
            @test new_env.mu == 2.0
            @test new_env.sigma == 3.0
            # Original environment should be unchanged
            original_env = model.evaluation_env
            @test original_env.mu != 2.0
            @test original_env.sigma != 3.0
        end
        
        @testset "subgraph function tests" begin
            model = create_test_model()
            
            @testset "with Markov blanket" begin
                keep_vars = [@varname(mu)]
                sub_model = subgraph(model, keep_vars)
                @test @varname(mu) ∈ sub_model.parameters
            end
            
            @testset "without Markov blanket" begin
                keep_vars = [@varname(mu), @varname(sigma)]
                sub_model = subgraph(model, keep_vars, include_markov_blanket=false)
                @test Set(sub_model.parameters) == Set(keep_vars)
            end
        end
        
        @testset "decondition helper function tests" begin
            
            @testset "parse_deconditioning_spec tests" begin
                # Symbol input
                result = parse_deconditioning_spec(:mu)
                @test result == [@varname(mu)]
                
                # VarName input
                result = parse_deconditioning_spec(@varname(mu))
                @test result == [@varname(mu)]
                
                # Vector input
                result = parse_deconditioning_spec([:mu, :sigma])
                @test result == [@varname(mu), @varname(sigma)]
            end
            
            @testset "check_deconditioning_validity tests" begin
                model = create_test_model()
                
                # Condition a variable first
                cond_model = condition(model, Dict(:mu => 1.0))
                
                # Valid decondition
                vars = [@varname(mu)]
                @test_nowarn check_deconditioning_validity(cond_model, vars)
                
                # Invalid: unobserved variable
                vars = [@varname(sigma)]  # not conditioned
                @test_throws ArgumentError check_deconditioning_validity(cond_model, vars)
            end
            
            @testset "mark_as_unobserved tests" begin
                model = create_test_model()
                # First condition to make variables observed
                cond_model = condition(model, Dict(:mu => 1.0, :sigma => 0.5))
                
                vars = [@varname(mu)]
                new_graph = mark_as_unobserved(cond_model.g, vars)
                
                @test !new_graph[@varname(mu)].is_observed
                @test new_graph[@varname(sigma)].is_observed  # unchanged
                # Original graph should be unchanged
                @test cond_model.g[@varname(mu)].is_observed
            end
            
            @testset "reset_evaluation_env tests" begin
                model = create_test_model()
                base_env = model.evaluation_env
                
                # Create modified environment
                modified_env = update_evaluation_env(base_env, Dict(@varname(mu) => 999.0))
                
                # Reset specific variables
                vars = [@varname(mu)]
                reset_env = reset_evaluation_env(modified_env, vars, base_env)
                
                @test reset_env.mu == base_env.mu  # reset
                # Other variables should be unchanged from modified_env
            end
        end
    end
    
    @testset "condition/decondition integration tests (from graphs.jl)" begin
        # Model definition from graphs.jl
        test_model = @bugs begin
            a ~ dnorm(f, c)
            f = b - 1
            b ~ dnorm(0, 1)
            c ~ dnorm(l, 1)
            g = a * 2
            d ~ dnorm(g, 1)
            h = g + 2
            e ~ dnorm(h, i)
            i ~ dnorm(0, 1)
            l ~ dnorm(0, 1)
        end

        inits = (
            a=1.0,
            b=2.0,
            c=3.0,
            d=4.0,
            e=5.0,
            i=4.0,
            l=-2.0,
        )

        model = compile(test_model, NamedTuple(), inits)
        
        a = @varname a
        l = @varname l
        c = @varname c

        @testset "condition with subgraph creation" begin
            # Condition on all variables except c (use current values from model)
            vars_to_condition = setdiff(model.parameters, [c])
            cond_model = condition(model, vars_to_condition)
            
            # tests for MarkovBlanketBUGSModel constructor
            @test cond_model.parameters == [c]
            @test Set(Symbol.(cond_model.flattened_graph_node_data.sorted_nodes)) ==
                Set([:l, :a, :b, :f, :c])
        end
        
        @testset "decondition functionality" begin
            # First condition on all except c
            vars_to_condition = setdiff(model.parameters, [c])
            cond_model = condition(model, vars_to_condition)
            
            # Then decondition a and l
            decond_model = decondition(cond_model, [a, l])
            @test Set(Symbol.(decond_model.parameters)) == Set([:a, :c, :l])
            @test Set(Symbol.(decond_model.flattened_graph_node_data.sorted_nodes)) ==
                Set([:l, :b, :f, :a, :d, :e, :c, :h, :g, :i])
        end
        
        @testset "log probability evaluation after conditioning" begin
            # Condition on all variables except c
            vars_to_condition = setdiff(model.parameters, [c])
            cond_model = condition(model, vars_to_condition)
            
            c_value = 4.0
            mb_logp = begin
                logp = 0
                f = 2.0 - 1.0
                logp += logpdf(dnorm(f, c_value), 1.0) # a
                logp += logpdf(dnorm(0.0, 1.0), 2.0) # b
                logp += logpdf(dnorm(0.0, 1.0), -2.0) # l
                logp += logpdf(dnorm(-2.0, 1.0), c_value) # c
                logp
            end

            # order: b, l, c, a
            @test mb_logp ≈ evaluate!!(cond_model, [c_value])[2] rtol = 1e-8
        end
        
        @testset "full model log probability evaluation" begin
            @test begin
                logp = 0
                logp += logpdf(dnorm(1.0, 3.0), 1.0) # a, where f = 1.0
                logp += logpdf(dnorm(0.0, 1.0), 2.0) # b
                logp += logpdf(dnorm(0.0, 1.0), -2.0) # l
                logp += logpdf(dnorm(-2.0, 1.0), 3.0) # c
                logp += logpdf(dnorm(0.0, 1.0), 4.0) # i
                logp += logpdf(dnorm(2.0, 1.0), 4.0) # d, where g = 2.0
                logp += logpdf(dnorm(4.0, 4.0), 5.0) # e, where h = 4.0
                logp
            end ≈ evaluate!!(model, [-2.0, 4.0, 3.0, 2.0, 1.0, 4.0, 5.0])[2] atol = 1e-8
        end
    end
end