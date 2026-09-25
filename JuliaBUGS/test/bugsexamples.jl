using JuliaBUGS: BUGSExamples

@testset "BUGSExamples registry" begin
    volumes = BUGSExamples.volumes()

    @testset "every volume is registered and non-empty" begin
        @test keys(volumes) == (:volume_1, :volume_2, :volume_3)
        for (_, examples) in pairs(volumes)
            @test !isempty(examples)
            @test all(ex -> ex isa BUGSExamples.Example, values(examples))
        end
    end

    @testset "every example carries a name and its original program" begin
        for (vol, examples) in pairs(volumes), (key, ex) in pairs(examples)
            @testset "$vol.$key" begin
                @test !isempty(ex.name)
                @test !isempty(ex.original_syntax_program)
            end
        end
    end

    # Every example file assigns bare names into the one BUGSExamples module scope, so a
    # file that forgets one silently picks up the previous file's value. That is how
    # Volume_3/05_Hepatitis_ME.jl came to publish 05_Hepatitis.jl's reference results, and
    # how Volume_2/04_Biopsies.jl came to use 03_Multivariate_Orange_trees.jl's initial
    # values after misspelling its own as `intis`.
    #
    # `===` on an isbits NamedTuple compares by value, so two examples that legitimately
    # share identical small initial values would trip this. None do today.
    @testset "no example shares another's $field by identity" for field in (
        :reference_results, :inits, :inits_alternative
    )
        seen = IdDict{Any,Symbol}()
        for (vol, examples) in pairs(volumes), (key, ex) in pairs(examples)
            value = getfield(ex, field)
            (isnothing(value) || isempty(value)) && continue
            owner = get(seen, value, nothing)
            if owner !== nothing
                @info "$vol.$key shares $field with $owner"
            end
            @test owner === nothing
            seen[value] = Symbol(vol, :., key)
        end
    end

    # Volume 1 is already compiled by test/model/bugsmodel.jl; this covers the volumes
    # registered for the first time here.
    #
    # Which call works is per example, and this mirrors what docs/gen_examples.jl decides
    # for the documentation pages. Most of these models need their own initial values:
    # alligators and endo throw a DomainError without them. biopsies is the other way
    # round, because its initial values leave `missing` in the upper triangle of `error`,
    # which Multinomial rejects. So try inits first and fall back to bare.
    @testset "every newly registered example compiles" begin
        for vol in (:volume_2, :volume_3), (key, ex) in pairs(volumes[vol])
            @testset "$vol.$key" begin
                model = nothing
                if !isempty(ex.inits)
                    try
                        model = JuliaBUGS.compile(ex.model_def, ex.data, ex.inits)
                    catch
                        model = nothing
                    end
                end
                if model === nothing
                    model = JuliaBUGS.compile(ex.model_def, ex.data)
                end
                @test model isa JuliaBUGS.BUGSModel
            end
        end
    end

    @testset "list prints every example" begin
        out = sprint(BUGSExamples.list)
        for (vol, examples) in pairs(volumes)
            @test occursin(replace(titlecase(string(vol)), "_" => " "), out)
            for key in keys(examples)
                @test occursin(string(key), out)
            end
        end
    end
end
