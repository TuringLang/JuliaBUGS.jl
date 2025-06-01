include("front_matter.jl")

const TEST_GROUPS = Dict{String,Function}(
    "unit" => () -> begin
        @testset "Unit Tests" begin
            Documenter.doctest(JuliaBUGS; manual=false)
            include("utils.jl")
        end
    end,
    "parser and macros" => () -> begin
        include("parser/test_parser.jl")
        include("passes.jl")
        include("model_macro.jl")
    end,
    "graphs" => () -> include("graphs.jl"),
    "condition" => () -> include("model/abstractppl.jl"),
    "compilation" => () -> begin
        @testset "BUGS examples volume 1" begin
            @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
                m = JuliaBUGS.BUGSExamples.VOLUME_1[m]
                model = compile(m.model_def, m.data, m.inits)
            end
        end
        @testset "Some corner cases" begin
            include("bugs_primitives.jl")
            include("compile.jl")
        end
    end,
    "log_density" => () -> begin
        include("log_density.jl")
        include("model.jl")
    end,
    # "gibbs" => () -> include("gibbs.jl"),
    # "mcmchains" => () -> include("ext/mcmchains.jl"),
    # "experimental" =>
    #     () -> include("experimental/ProbabilisticGraphicalModels/bayesnet.jl"),
    # TODO: there is something wrong with source_gen tests, it hangs, fix this
    # "source_gen" => () -> include("source_gen.jl"),
)

raw_selection = get(ENV, "TEST_GROUP", "all")
selected_groups = Set(split(raw_selection, ','))

if "all" ∉ selected_groups
    unknown = setdiff(selected_groups, keys(TEST_GROUPS))
    if !isempty(unknown)
        error("Unknown test group(s): $(join(collect(unknown), ", "))")
    end
end

# Execute the requested tests.
if "all" in selected_groups
    @info "Running tests for ALL groups"
    for fn in values(TEST_GROUPS)
        fn()
    end
else
    @info "Running tests for groups: $(join(collect(selected_groups), ", "))"
    for g in selected_groups
        TEST_GROUPS[g]()
    end
end
