using JuliaBUGS

(;model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1.rats

model = compile(model_def, data, inits)

model.g
sorted_nodes = model.sorted_nodes


