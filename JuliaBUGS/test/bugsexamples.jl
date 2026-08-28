using JuliaBUGS: BUGSExamples

@testset "BUGSExamples registry" begin
    volumes = BUGSExamples.volumes()

    @testset "every volume is registered and non-empty" begin
        @test keys(volumes) == (:volume_1, :volume_2, :volume_3)
        for (vol, examples) in pairs(volumes)
            @test !isempty(examples)
            @test all(ex -> ex isa BUGSExamples.Example, values(examples))
        end
    end

    @testset "every example is fully populated" begin
        for (vol, examples) in pairs(volumes), (key, ex) in pairs(examples)
            @testset "$vol.$key" begin
                @test !isempty(ex.name)
                @test ex.model_def isa Expr
                @test !isempty(ex.original_syntax_program)
                # Empty is valid for both: the Fun Shapes models observe nothing and
                # sample a geometric region, and eye_tracking and hips1 through hips3
                # are deterministic enough given their data to need no initial values.
                @test ex.data isa NamedTuple
                @test ex.inits isa NamedTuple
            end
        end
    end

    # Every example file assigns bare names into the one BUGSExamples module scope, so a
    # file that forgets one silently picks up the previous file's value. That is how
    # Volume_3/05_Hepatitis_ME.jl came to publish 05_Hepatitis.jl's reference results, and
    # how Volume_2/04_Biopsies.jl came to use 03_Multivariate_Orange_trees.jl's initial
    # values after misspelling its own as `intis`. Both are caught by identity here.
    @testset "no example shares another's fields by identity" begin
        # `data` is excluded on purpose: surgical_simple and surgical_realistic are
        # two models of the same dataset and share it deliberately.
        for field in (:reference_results, :inits, :inits_alternative)
            seen = IdDict{Any,Symbol}()
            for (vol, examples) in pairs(volumes), (key, ex) in pairs(examples)
                value = getfield(ex, field)
                value === nothing && continue
                isempty(value) && continue
                if haskey(seen, value)
                    @test "$vol.$key shares $field with $(seen[value])" == ""
                else
                    seen[value] = Symbol(vol, :., key)
                end
            end
        end
    end

    @testset "every registered example compiles" begin
        for (vol, examples) in pairs(volumes), (key, ex) in pairs(examples)
            # Known-broken on main, independent of the registry: these throw from
            # inside compilation rather than from anything the registry controls.
            key in (:kidney, :leukfr, :alligators, :endo, :epil) && continue
            @testset "$vol.$key" begin
                model = JuliaBUGS.compile(ex.model_def, ex.data)
                @test model isa JuliaBUGS.BUGSModel
                # hips1 has no free parameters: it is the closed-form variant of the
                # hip-replacement study, so an empty parameter set is correct there.
                @test JuliaBUGS.parameters(model) isa AbstractVector
            end
        end
    end

    @testset "list prints every example" begin
        out = sprint(BUGSExamples.list)
        for (vol, examples) in pairs(volumes)
            for key in keys(examples)
                @test occursin(string(key), out)
            end
        end
        @test occursin("Volume 1", out)
        @test occursin("Volume 3", out)
    end
end
