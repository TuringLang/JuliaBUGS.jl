# Tests for abstractppl.jl functions, specifically condition and decondition

using Test
using JuliaBUGS
using AbstractPPL
using Random
using Distributions

# Include the new condition implementation
include("../../src/model/condition_new.jl")

@testset "new_condition implementation tests" begin
    
    # Create a simple test model
    function create_test_model()
        model_def = @bugs begin
            mu ~ Normal(0, 10)
            sigma ~ Uniform(0, 10)
            for i in 1:3
                x[i] ~ Normal(mu, sigma)
            end
            y ~ Normal(sum(x[:]), 1)
        end
        data = (; y = 5.0)
        return compile(model_def, data)
    end
    
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
            spec = (; mu=1.0, sigma=2.0)
            result = parse_conditioning_spec(spec, model)
            @test result[@varname(mu)] == 1.0
            @test result[@varname(sigma)] == 2.0
        end
    end
    
    @testset "check_conditioning_validity tests" begin
        model = create_test_model()
        
        @testset "valid variables" begin
            # Should not throw
            check_conditioning_validity(model, [@varname(mu), @varname(sigma)])
        end
        
        @testset "non-existent variable" begin
            @test_throws ArgumentError check_conditioning_validity(model, [@varname(nonexistent)])
        end
        
        @testset "deterministic variable" begin
            # Create a model with deterministic variables
            model_def = @bugs begin
                a ~ Normal(0, 1)
                b = a + 1  # deterministic
                c ~ Normal(b, 1)
            end
            model = compile(model_def, (; c = 1.0))
            
            @test_throws ArgumentError check_conditioning_validity(model, [@varname(b)])
        end
        
        @testset "already observed variable" begin
            # For our test model, let's check an already observed variable
            # First, let's create a model where we mark something as observed
            test_model = create_test_model()
            # Mark mu as observed first
            test_model.g[@varname(mu)] = BangBang.setproperty!!(test_model.g[@varname(mu)], :is_observed, true)
            
            @test_logs (:warn,) check_conditioning_validity(test_model, [@varname(mu)])
        end
    end
    
    @testset "mark_as_observed tests" begin
        model = create_test_model()
        original_graph = model.g
        
        # Mark mu and sigma as observed
        new_graph = mark_as_observed(original_graph, [@varname(mu), @varname(sigma)])
        
        # Check that original graph is unchanged
        @test !original_graph[@varname(mu)].is_observed
        @test !original_graph[@varname(sigma)].is_observed
        
        # Check that new graph has marked variables
        @test new_graph[@varname(mu)].is_observed
        @test new_graph[@varname(sigma)].is_observed
        
        # Check that other variables are unchanged
        @test new_graph[@varname(x[1])].is_observed == original_graph[@varname(x[1])].is_observed
    end
    
    @testset "update_evaluation_env tests" begin
        model = create_test_model()
        original_env = model.evaluation_env
        
        var_values = Dict(@varname(mu) => 2.0, @varname(sigma) => 3.0)
        new_env = update_evaluation_env(original_env, var_values)
        
        # Check updates
        @test new_env.mu == 2.0
        @test new_env.sigma == 3.0
        
        # Check that original is unchanged
        @test original_env.mu != 2.0
        @test original_env.sigma != 3.0
    end
    
    @testset "new_condition function tests" begin
        
        @testset "Dict input" begin
            model = create_test_model()
            original_params = copy(model.parameters)
            
            # Condition on mu
            cond_model = new_condition(model, Dict(:mu => 1.5))
            
            @test cond_model.evaluation_env.mu == 1.5
            @test cond_model.g[@varname(mu)].is_observed
            @test @varname(mu) ∉ cond_model.parameters
            @test @varname(sigma) ∈ cond_model.parameters
            @test length(cond_model.parameters) == length(original_params) - 1
            
            # Check Markov blanket is computed
            @test @varname(x[1]) ∈ cond_model.flattened_graph_node_data.sorted_nodes
        end
        
        @testset "Vector input" begin
            model = create_test_model()
            model = initialize!(model, (; mu=2.5, sigma=1.0))
            
            cond_model = new_condition(model, [:mu, :sigma])
            
            @test cond_model.evaluation_env.mu == 2.5
            @test cond_model.evaluation_env.sigma == 1.0
            @test cond_model.g[@varname(mu)].is_observed
            @test cond_model.g[@varname(sigma)].is_observed
            @test isempty(setdiff(cond_model.parameters, [@varname(x[1]), @varname(x[2]), @varname(x[3])]))
        end
        
        @testset "Pairs input" begin
            model = create_test_model()
            
            cond_model = new_condition(model, :mu => 1.5, :sigma => 2.0)
            
            @test cond_model.evaluation_env.mu == 1.5
            @test cond_model.evaluation_env.sigma == 2.0
            @test cond_model.g[@varname(mu)].is_observed
            @test cond_model.g[@varname(sigma)].is_observed
        end
        
        @testset "NamedTuple input" begin
            model = create_test_model()
            
            cond_model = new_condition(model, (; mu=1.5, sigma=2.0))
            
            @test cond_model.evaluation_env.mu == 1.5
            @test cond_model.evaluation_env.sigma == 2.0
            @test cond_model.g[@varname(mu)].is_observed
            @test cond_model.g[@varname(sigma)].is_observed
        end
        
        @testset "create_subgraph option" begin
            model = create_test_model()
            
            # With subgraph (default)
            cond_with_subgraph = new_condition(model, Dict(:mu => 1.5))
            
            # Without subgraph
            cond_without_subgraph = new_condition(model, Dict(:mu => 1.5), create_subgraph=false)
            
            # Both should have same conditioning
            @test cond_with_subgraph.evaluation_env.mu == cond_without_subgraph.evaluation_env.mu
            @test cond_with_subgraph.g[@varname(mu)].is_observed == cond_without_subgraph.g[@varname(mu)].is_observed
            
            # When create_subgraph=false, we keep all original nodes
            # The test model is small, so the difference might not be apparent
            # Let's just check they have the expected nodes
            @test @varname(mu) ∉ cond_with_subgraph.parameters
            @test @varname(mu) ∉ cond_without_subgraph.parameters
            @test length(cond_without_subgraph.flattened_graph_node_data.sorted_nodes) >= 
                  length(cond_with_subgraph.flattened_graph_node_data.sorted_nodes)
        end
        
        @testset "error handling" begin
            model = create_test_model()
            
            # Non-existent variable
            @test_throws ArgumentError new_condition(model, Dict(:nonexistent => 1.0))
            
            # Deterministic variable
            model_def = @bugs begin
                a ~ Normal(0, 1)
                b = a + 1
            end
            model = compile(model_def, NamedTuple())
            @test_throws ArgumentError new_condition(model, Dict(:b => 1.0))
        end
        
        @testset "complex model conditioning" begin
            # Test with a more complex hierarchical model
            model_def = @bugs begin
                # Hyperparameters
                alpha ~ Normal(0, 10)
                beta ~ Normal(0, 10)
                tau ~ Gamma(1, 1)
                
                # Group-level parameters
                for i in 1:3
                    theta[i] ~ Normal(alpha + beta * i, tau)
                end
                
                # Observations
                for i in 1:3
                    for j in 1:5
                        y[i,j] ~ Normal(theta[i], 1)
                    end
                end
            end
            
            y_data = randn(3, 5)
            model = compile(model_def, (; y=y_data))
            
            # Condition on hyperparameters
            cond_model = new_condition(model, Dict(:alpha => 1.0, :beta => 0.5))
            
            @test cond_model.evaluation_env.alpha == 1.0
            @test cond_model.evaluation_env.beta == 0.5
            @test @varname(tau) ∈ cond_model.parameters
            @test all(i -> @varname(theta[i]) ∈ cond_model.parameters, 1:3)
            
            # Should include theta variables in Markov blanket
            @test all(i -> @varname(theta[i]) ∈ cond_model.flattened_graph_node_data.sorted_nodes, 1:3)
        end
    end
    
    @testset "subgraph function tests" begin
        model = create_test_model()
        
        @testset "with Markov blanket" begin
            sub_model = subgraph(model, [@varname(mu)])
            
            # Should include mu and its Markov blanket
            @test @varname(mu) ∈ sub_model.flattened_graph_node_data.sorted_nodes
            @test @varname(x[1]) ∈ sub_model.flattened_graph_node_data.sorted_nodes
            @test @varname(x[2]) ∈ sub_model.flattened_graph_node_data.sorted_nodes
            @test @varname(x[3]) ∈ sub_model.flattened_graph_node_data.sorted_nodes
        end
        
        @testset "without Markov blanket" begin
            sub_model = subgraph(model, [@varname(mu)], include_markov_blanket=false)
            
            # Should only include mu
            @test sub_model.flattened_graph_node_data.sorted_nodes == [@varname(mu)]
        end
    end
    
    @testset "integration with existing condition function" begin
        # Ensure the new implementation can work alongside the old one
        model = create_test_model()
        
        # Use new_condition
        new_cond = new_condition(model, Dict(:mu => 1.0))
        
        # Basic checks
        @test @varname(mu) ∉ new_cond.parameters
        @test new_cond.evaluation_env.mu == 1.0
        @test new_cond.g[@varname(mu)].is_observed
    end
end