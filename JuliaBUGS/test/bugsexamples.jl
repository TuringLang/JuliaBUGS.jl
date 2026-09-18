using JuliaBUGS: BUGSExamples

@testset "BUGSExamples" begin
    @testset "reading a folder" begin
        dir = mktempdir()
        write(joinpath(dir, "example.toml"), "name = \"Toy\"\n")
        write(
            joinpath(dir, "model.bugs"),
            """
            model {
                for (i in 1:2) { y[i] ~ dnorm(mu.x, 1) }
                mu.x ~ dnorm(0, 1)
            }
            """,
        )
        write(
            joinpath(dir, "data.json"),
            """{"y": [1.5, null], "m": [[1, 2], [3, 4]], "c": [[[1], [2]], [[3], [4]]], "n": 2, "x": 2.0}""",
        )
        ex = BUGSExamples.load(dir)

        @test ex isa BUGSExamples.Example
        @test ex.name == "Toy"
        @test ex.path == dir
        @test ex.model_def isa JuliaBUGS.BUGSModelDef
        @test ex.model_def.model_def ==
            JuliaBUGS.BUGSModelDef(ex.original_syntax_program; replace_period=false).model_def
        @test ex.data.y isa Vector{Union{Missing,Float64}}
        @test isequal(ex.data.y, [1.5, missing])
        @test ex.data.m == [1 2; 3 4]
        @test ex.data.m isa Matrix{Int}
        @test size(ex.data.c) == (2, 2, 1)
        @test ex.data.c[2, 1, 1] == 3
        @test ex.data.n === 2
        @test ex.data.x === 2.0
        @test ex.inits === NamedTuple()
        @test ex.reference_results === nothing
    end

    @testset "registry" begin
        volumes = BUGSExamples.volumes()
        @test keys(volumes) == (:volume_1, :volume_2, :volume_3)
        @test volumes.volume_1 === BUGSExamples.VOLUME_1
        @test BUGSExamples.VOLUME_1.rats === BUGSExamples.rats
        @test BUGSExamples.load(:rats) isa BUGSExamples.Example
        @test BUGSExamples.load(:volume_2, :dugongs).name == BUGSExamples.dugongs.name
        for (volume, examples) in pairs(volumes), (key, ex) in pairs(examples)
            @test !isempty(ex.name)
            @test isdir(ex.path)
        end
    end

    @testset "blocked and lazy examples stay out of the volumes" begin
        registered = Set(
            e.key for e in BUGSExamples.ENTRIES if e.blocked === nothing && !e.lazy
        )
        for (_, examples) in pairs(BUGSExamples.volumes())
            @test Set(keys(examples)) ⊆ registered
        end
        @test :inhalers ∉ keys(BUGSExamples.VOLUME_1)
        @test :methadone ∉ registered
        @test_throws ErrorException BUGSExamples.load(:no_such_example)
    end

    @testset "list prints every entry" begin
        out = sprint(BUGSExamples.list)
        for e in BUGSExamples.ENTRIES
            @test occursin(string(e.key), out)
        end
        @test occursin("[blocked:", out)
        @test occursin("[load on demand]", out)
    end

    # Volume 1 is compiled by test/model/bugsmodel.jl. Most of these need their own initial
    # values, and a few only compile without them, so try inits first and fall back to bare.
    @testset "every Volume 2 and 3 example compiles" begin
        for volume in (:volume_2, :volume_3),
            (key, ex) in pairs(BUGSExamples.volumes()[volume])

            @testset "$volume.$key" begin
                model = nothing
                if !isempty(ex.inits)
                    model = try
                        JuliaBUGS.compile(ex.model_def, ex.data, ex.inits)
                    catch
                        nothing
                    end
                end
                if model === nothing
                    model = JuliaBUGS.compile(ex.model_def, ex.data)
                end
                @test model isa JuliaBUGS.BUGSModel
            end
        end
    end
end
