using BUGSExamples
using Test

@testset "BUGSExamples.jl" begin
    @testset "module surface" begin
        @test isdefined(BUGSExamples, :BUGSExample)
        @test isdefined(BUGSExamples, :ReferenceResults)
        @test isdefined(BUGSExamples, :VOLUME_1)
        @test BUGSExamples.examples() isa NamedTuple
        @test !isempty(BUGSExamples.examples())
    end

    @testset "rats" begin
        ex = BUGSExamples.rats
        @test ex isa BUGSExamples.BUGSExample
        @test ex.volume == 1
        @test ex.order == 1
        @test ex.doodlebugs_id == "rats"
        @test ex.citations == ["gelfand1990"]
        @test !isempty(ex.original_syntax_program)
        @test !isempty(ex.model_def)
        @test !isempty(ex.model_function)
        @test size(ex.data.Y) == (30, 5)
        @test ex.data.N == 30
        @test ex.data.T == 5
        @test ex.reference_results !== nothing
        @test ex.reference_results.params.alpha0.mean == 106.6
        @test ex.reference_results.meta.source == "reference"
        @test ex.sampled_results === nothing
        @test isfile(BUGSExamples.path(ex, "model.jl"))
        @test isfile(BUGSExamples.path(ex, "model.bugs"))
    end

    @testset "pumps" begin
        ex = BUGSExamples.pumps
        @test ex isa BUGSExamples.BUGSExample
        @test ex.volume == 1
        @test ex.order == 2
        @test ex.doodlebugs_id == "pumps"
        @test ex.data.N == 10
        @test length(ex.data.t) == 10
        @test !isempty(ex.model_function)
        @test ex.reference_results === nothing
    end

    @testset "VOLUME_1 contents and ordering" begin
        keys_in_order = collect(keys(BUGSExamples.VOLUME_1))
        @test keys_in_order == [:rats, :pumps, :dogs, :seeds, :surgical_simple, :surgical_realistic]
        for (_, ex) in pairs(BUGSExamples.VOLUME_1)
            @test ex.volume == 1
            @test !isempty(ex.original_syntax_program)
            @test !isempty(ex.model_def)
        end
    end
end
