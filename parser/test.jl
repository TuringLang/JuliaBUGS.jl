using Test

@testset "skip_trivia!" begin
    text = "  \n a"
    tv = tokenize(text)
    diagnostics = []
    jp = []
    loc = skip_trivia!(tv1, 1, text, jp, diagnostics)
    @show loc
    @show jp
end

@testset "expect!" begin
    text = "{}"
    tv = tokenize(text)
    diagnostics = []
    jp = []
    loc = expect!(tv, 1, text, jp, diagnostics, K"{", false)
    @show loc
    @show jp
    loc = expect!(tv, loc, text, jp, diagnostics, K"}", true, "end")
    @show loc
    @show jp
end

