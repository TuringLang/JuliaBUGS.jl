using JuliaBUGS

bugs_model = @bugs begin
    a ~ Normal(0, 1)
    
    b = a
    
    b ~ Normal(1, 2)
end
model = compile(bugs_model, (;), (;))