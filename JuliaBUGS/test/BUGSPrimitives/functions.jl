@testset "inprod(a,b)" begin
    A = [3, 0.7, 6]
    B = [2.6, 1.3, 3]
    @test JuliaBUGS.BUGSPrimitives.inprod(A, B) == 26.71
end

@testset "step(x)" begin
    @test JuliaBUGS.BUGSPrimitives._step.([-1, 0, 1]) == [0, 1, 1]
end
