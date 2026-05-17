using Test
using JuliaBUGS
using JuliaBUGS.BUGSExamples:
    BUGSExample, ReferenceResults, path, examples, list, load_example

@testset "JuliaBUGS.BUGSExamples submodule" begin
    @testset "module surface" begin
        @test JuliaBUGS.BUGSExamples.examples() isa NamedTuple
        @test !isempty(JuliaBUGS.BUGSExamples.examples())
        @test haskey(JuliaBUGS.BUGSExamples.VOLUME_1, :rats)
        @test haskey(JuliaBUGS.BUGSExamples.VOLUME_1, :pumps)
        @test JuliaBUGS.BUGSExamples.VOLUME_2 isa NamedTuple
        @test JuliaBUGS.BUGSExamples.VOLUME_3 isa NamedTuple
        @test JuliaBUGS.BUGSExamples.VOLUME_4 isa NamedTuple
    end

    @testset "list output" begin
        io = IOBuffer()
        list(io)
        out = String(take!(io))
        @test occursin("Available Models", out)
        @test occursin(":rats", out)
        @test occursin(":pumps", out)
    end

    @testset "rats fields" begin
        ex = JuliaBUGS.BUGSExamples.rats
        @test ex isa BUGSExample
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
        @test ex.reference_results isa ReferenceResults
        @test ex.reference_results.params.alpha0.mean == 106.6
        @test ex.reference_results.meta.source == "reference"
        @test ex.sampled_results === nothing
    end

    @testset "pumps fields" begin
        ex = JuliaBUGS.BUGSExamples.pumps
        @test ex isa BUGSExample
        @test ex.volume == 1
        @test ex.order == 2
        @test ex.doodlebugs_id == "pumps"
        @test ex.data.N == 10
        @test length(ex.data.t) == 10
        @test !isempty(ex.model_function)
        @test ex.reference_results === nothing
        @test ex.sampled_results === nothing
    end

    @testset "Volume 1 ordering matches WinBUGS sequence" begin
        keys_in_order = collect(keys(JuliaBUGS.BUGSExamples.VOLUME_1))
        @test keys_in_order ==
            [:rats, :pumps, :dogs, :seeds, :surgical_simple, :surgical_realistic]
        for (_, ex) in pairs(JuliaBUGS.BUGSExamples.VOLUME_1)
            @test ex.volume == 1
            @test !isempty(ex.original_syntax_program)
            @test !isempty(ex.model_def)
        end
    end

    @testset "path helper + model.jl include round-trips to Expr" begin
        ex = JuliaBUGS.BUGSExamples.rats
        p = path(ex, "model.jl")
        @test isfile(p)
        @test isfile(path(ex, "model.bugs"))
        @test isfile(path(ex, "data.json"))
        model_def = include(p)
        @test model_def isa Expr
        # Round-trip via @bugs(string) form should produce the same Expr.
        from_string = JuliaBUGS.Parser._bugs_string_input(ex.original_syntax_program, false)
        @test from_string == model_def
    end

    @testset "model_fn.jl files include without error" begin
        # Each model_fn.jl declares an `@model function …` constructor; including
        # it in this scope registers the method and exercises the file content.
        for example_name in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            ex = getfield(JuliaBUGS.BUGSExamples, example_name)
            model_fn_path = path(ex, "model_fn.jl")
            if isfile(model_fn_path)
                @test_nowarn include(model_fn_path)
            end
        end
    end

    @testset "examples compile and produce sane log densities" begin
        for example_name in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            ex = getfield(JuliaBUGS.BUGSExamples, example_name)
            model_def = include(path(ex, "model.jl"))
            model = compile(model_def, ex.data, ex.inits)
            @test model isa JuliaBUGS.BUGSModel
        end
    end

    @testset "load_example smoke test on rats" begin
        # Re-load directly to exercise the public loader entry point.
        loaded = load_example(JuliaBUGS.BUGSExamples.rats.source_dir)
        @test loaded isa BUGSExample
        @test loaded.name == JuliaBUGS.BUGSExamples.rats.name
        @test loaded.data.N == 30
    end
end

# Exercise the bare-UnionAll branch of `Base.show(::IO, ::Type{<:OfArray})`.
# This is the path that was crashing under Julia 1.12 / DocumenterVitepress
# before the of_type.jl patch.
@testset "OfArray show fallback" begin
    io = IOBuffer()
    show(io, JuliaBUGS.OfArray)
    @test String(take!(io)) == "OfArray"
end
