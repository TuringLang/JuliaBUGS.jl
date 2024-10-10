using JuliaBUGS: CompilerUtils

@testset "Decompose for loop" begin
    ex = MacroTools.@q for i in 1:3
        x[i] = i
        for j in 1:3
            y[i, j] = i + j
        end
    end

    loop_var, lb, ub, body = JuliaBUGS.decompose_for_expr(ex)
    
    @test loop_var == :i
    @test lb == 1
    @test ub == 3
    @test body == MacroTools.@q begin
        x[i] = i
        for j in 1:3
            y[i, j] = i + j
        end
    end
end
