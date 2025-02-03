using JuliaBUGS

(; model_def, data) = JuliaBUGS.BUGSExamples.rats

model = compile(model_def, data)

ni = model.g[@varname(var"beta.tau")]
nf = ni.node_function

nf(model.evaluation_env, ())

model.g[@varname(Y[1, 1])] 

vn

using AbstractPPL
getsym(vn)
getoptic(vn)

y = rand(5, 5)

getoptic(vn)(y)

AbstractPPL.get(model.evaluation_env, vn)

ex = :(
function foo(x)
    return JuliaBUGS.dnorm(x, 1)
end
)

Base.eval(:(using JuliaBUGS))

f = Base.eval(ex)

dist = f(1)

f
