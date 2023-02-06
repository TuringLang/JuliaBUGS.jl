using Test

include("compiler.jl")

# tests for `eval` function
@test eval(1, Dict()) == 1
@test eval(:(x[i]), Dict(:x => [1, 2, 3], :i => 2)) == 2
@test eval(:(x[y[1] + 1]), Dict(:y => [1, 2, 3], :x => [1, 2, 3])) == 2
@test eval(:(x[y[1] + 1]), Dict(:x => [1, 2, 3])) == :(x[y[1] + 1])

# tests for `variables` function
cd = CompilerData()
variables(:(x[i]), Dict(:i=>1), cd) == Set([(:x, 1)])
variables(:(x[1]), Dict(:x => [1, 2, 3]), cd) == Set()
variables(:(x[1, 1:2]), Dict(), cd) == Set([(:x, 1, 1), (:x, 1, 2)])

